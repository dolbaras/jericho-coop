# Install the co-op mod into a game folder: <game>\bin\dinput8.dll and <game>\coop\*.lua.
# Backs up an existing dinput8.dll that is not ours.
# -Anims also builds <game>\Pack1.packed (first-person scene animations retargeted to the
# full character models, from the game's own Data*.packed by tools\cm3_retarget.py; needs
# Python 3). Only the experimental own-character cutscene view (povall=true) uses it.
# Usage: install.ps1 -Game <game dir> [-Anims] [-RebuildAnims]
param(
    [Parameter(Mandatory)] [string] $Game,
    [switch] $Anims,
    [switch] $RebuildAnims,
    [switch] $SkipAnims
)
$root = Split-Path $PSScriptRoot -Parent
$dll = Join-Path $root "native\build\dinput8.dll"
$bin = Join-Path $Game "bin"
if (-not (Test-Path (Join-Path $bin "Jericho.exe"))) { throw "Jericho.exe not found in $bin" }
$target = Join-Path $bin "dinput8.dll"
if ((Test-Path $target) -and -not (Select-String -Path $target -Pattern "CoopHost" -SimpleMatch -Quiet)) {
    Copy-Item $target "$target.orig" -Force
    "backed up existing dinput8.dll"
}
Copy-Item $dll $target -Force
$coop = Join-Path $Game "coop"
New-Item -ItemType Directory -Force $coop | Out-Null
Copy-Item (Join-Path $root "lua\*.lua") $coop -Force

# Scene animations for the own-character cutscene view (experiment; the default view is
# the original scene camera and needs none).
$pack = Join-Path $Game "Pack1.packed"
if (-not $SkipAnims -and ($RebuildAnims -or ($Anims -and -not (Test-Path $pack)))) {
    if ((Test-Path $pack) -and -not (Select-String -Path $pack -Pattern "coopbody_" -SimpleMatch -Quiet)) {
        Write-Warning "$pack exists and is not the co-op animation pack: left alone (scene bodies use raw poses)"
    } else {
        $py = Get-Command py -ErrorAction SilentlyContinue
        $pyArgs = @("-3")
        if (-not $py) { $py = Get-Command python -ErrorAction SilentlyContinue; $pyArgs = @() }
        if (-not $py) {
            Write-Warning "Python 3 not found: Pack1.packed not built (install Python and run install.ps1 -RebuildAnims)"
        } else {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "jericho-coop-anims"
            "building scene animations (a few minutes)..."
            & $py.Source @pyArgs -I (Join-Path $PSScriptRoot "cm3_retarget.py") --game $Game --out $tmp batch --pack "$pack.tmp"
            if ($LASTEXITCODE -eq 0 -and (Test-Path "$pack.tmp")) {
                Move-Item "$pack.tmp" $pack -Force
                "built $pack"
            } else {
                Remove-Item "$pack.tmp" -ErrorAction SilentlyContinue
                Write-Warning "animation build failed (exit $LASTEXITCODE); the mod works without it"
            }
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
"installed to $Game"

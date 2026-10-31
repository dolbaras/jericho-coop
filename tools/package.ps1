# Build the release archive dist\jericho-coop-<version>.zip:
#   Install Co-op.bat + coop-installer.ps1   the installer (backs up what it replaces, uninstalls)
#   files\                                   what goes into the game folder (bin\dinput8.dll,
#                                            coop\*.lua, the cutscene animation builder,
#                                            coop\coop-launcher.ps1 behind the shortcut)
#   README-COOP.txt, LICENSE.txt, ENET-LICENSE.txt, STEAM-NOTICE.txt
# files\coop\steam_api.dll (Steam joining, native/steam_net.c) comes from
# <workspace>\tools\steam: Steamworks.NET Standalone 2025.164.1, Windows-x86, SHA-256 checked.
# Run native\build.sh first. The test helpers (dev.lua, probe.lua) are left out.
# Usage: package.ps1 -Version 0.2 [-Exe] [-Dist <folder>]
# -Exe also builds dist\jericho-coop-setup-<version>.exe: a single-file installer that carries this zip (an ADDITIONAL release
# asset; the zip stays the one the shortcut's launcher updates from). Made by <workspace>\tools\mkinstaller (-Mkinstaller <folder>
# for a clone placed elsewhere); the exe is unsigned. -Dist: write to that folder instead of dist\ (tests: dist\ holds the published zips).
param([Parameter(Mandatory)] [string] $Version, [switch] $Exe, [string] $Mkinstaller = "", [string] $Dist = "")
$root = Split-Path $PSScriptRoot -Parent
# Players of different versions are kept apart by Coop.VERSION (lobby check): it must be this one.
$luaVersion = (Select-String -Path (Join-Path $root "lua\coop.lua") -Pattern '^Coop.VERSION = "([^"]+)"').Matches[0].Groups[1].Value
if ($luaVersion -ne $Version) { throw "lua\coop.lua has Coop.VERSION = $luaVersion, not $Version" }
$dll = Join-Path $root "native\build\dinput8.dll"
if (-not (Test-Path $dll)) { throw "build native\build\dinput8.dll first (sh native/build.sh)" }
$dist = if ($Dist) { $Dist } else { Join-Path $root "dist" }
New-Item -ItemType Directory -Force $dist | Out-Null
$stage = Join-Path $dist "jericho-coop-$Version"
$files = Join-Path $stage "files"
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $files "bin"), (Join-Path $files "coop") | Out-Null
Copy-Item $dll (Join-Path $files "bin")
$steam = Join-Path $root "..\..\..\tools\steam\steam_api.dll"
$steamSha = "FDAFB7C65EC7D4182B42BF92CC8671C68E4DC547CC6E613899D2618A47EB65DA"
if (-not (Test-Path $steam)) { throw "tools\steam\steam_api.dll missing (Steamworks.NET Standalone 2025.164.1, Windows-x86)" }
$sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([IO.File]::ReadAllBytes($steam))) -replace "-", ""
if ($sha -ne $steamSha) { throw "tools\steam\steam_api.dll is not the pinned one ($sha)" }
Copy-Item $steam (Join-Path $files "coop")
# files\coop\python: Python's official embeddable build (python.org 3.12.10, win32, PSF license
# in it), so the installer builds the cutscene animations and Ross's model without the player
# installing Python. <workspace>\tools\python-embed, SHA-256 checked.
$pyZip = Join-Path $root "..\..\..\tools\python-embed\python-3.12.10-embed-win32.zip"
$pySha = "084B9EB24CB848605C895D05B738FBC2572EFC8B4C18C415A824065864A2B853"
if (-not (Test-Path $pyZip)) { throw "tools\python-embed\python-3.12.10-embed-win32.zip missing (python.org)" }
$sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([IO.File]::ReadAllBytes($pyZip))) -replace "-", ""
if ($sha -ne $pySha) { throw "tools\python-embed zip is not the pinned one ($sha)" }
Expand-Archive $pyZip (Join-Path $files "coop\python")
Get-ChildItem (Join-Path $root "lua\*.lua") | Where-Object { $_.Name -notin "dev.lua", "probe.lua" } |
    Copy-Item -Destination (Join-Path $files "coop")
Set-Content -Path (Join-Path $files "coop\version.txt") -Value $Version -Encoding ASCII
# The animation builder the installer runs for the experimental "own eyes" cutscene view.
New-Item -ItemType Directory -Force (Join-Path $files "coop\anims") | Out-Null
Copy-Item (Join-Path $PSScriptRoot "cm3_retarget.py"), (Join-Path $PSScriptRoot "bfpk.py"), (Join-Path $PSScriptRoot "m3d.py") (Join-Path $files "coop\anims")
# The "Jericho Co-op+" shortcut's launcher: updates the mod from the GitHub releases, then starts the game.
Copy-Item (Join-Path $PSScriptRoot "launcher.ps1") (Join-Path $files "coop\coop-launcher.ps1")
# Every file of the payload: the installer checks the folder it got against it before touching
# the game (a 0.2.3 launcher started twice deleted the extracted files under the first one's
# installer, which then installed half of them and removed the rest as old).
$list = Get-ChildItem $files -Recurse -File | ForEach-Object { $_.FullName.Substring($files.Length + 1) }
Set-Content -Path (Join-Path $files "coop\payload.txt") -Value (@($list) + "coop\payload.txt") -Encoding ASCII
# Installer
Copy-Item (Join-Path $root "tools\installer.ps1") (Join-Path $stage "coop-installer.ps1")
Set-Content -Path (Join-Path $stage "Install Co-op.bat") -Encoding ASCII `
    -Value '@start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0coop-installer.ps1" %*'
Copy-Item (Join-Path $root "docs\release-readme.txt") (Join-Path $stage "README-COOP.txt")
Copy-Item (Join-Path $root "LICENSE") (Join-Path $stage "LICENSE.txt")
Copy-Item (Join-Path $root "docs\enet-license.txt") (Join-Path $stage "ENET-LICENSE.txt")
Copy-Item (Join-Path $root "docs\steam-notice.txt") (Join-Path $stage "STEAM-NOTICE.txt")
$zip = Join-Path $dist "jericho-coop-$Version.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
Remove-Item $stage -Recurse -Force
"packaged $zip"
if ($Exe) {
    $mk = if ($Mkinstaller) { $Mkinstaller } else { Join-Path $root "..\..\..\tools\mkinstaller" }
    $mkScript = Join-Path $mk "mkinstaller.ps1"
    if (-not (Test-Path $mkScript)) { throw "tools\mkinstaller\mkinstaller.ps1 missing (the workspace's tools folder; -Mkinstaller <folder>)" }
    $exeOut = Join-Path $dist "jericho-coop-setup-$Version.exe"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mkScript -Zip $zip -Out $exeOut -Product "Jericho Co-op+" -Version $Version `
        -Description "Jericho Co-op+ installer" -TempPrefix "jericho-coop-setup" -Accent "c42830"
    if ($LASTEXITCODE -ne 0) { throw "mkinstaller.ps1 failed" }
}

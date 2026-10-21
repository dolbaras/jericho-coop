# Build the release archive dist\jericho-coop-<version>.zip:
#   Install Co-op.bat + coop-installer.ps1   the installer (backs up what it replaces, uninstalls)
#   files\                                   what goes into the game folder (bin\dinput8.dll,
#                                            coop\*.lua, the cutscene animation builder)
#   README-COOP.txt, LICENSE.txt, ENET-LICENSE.txt, STEAM-NOTICE.txt
# files\coop\steam_api.dll (Steam joining, native/steam_net.c) comes from
# <workspace>	ools\steam: Steamworks.NET Standalone 2025.164.1, Windows-x86, SHA-256 checked.
# Run native\build.sh first. The test helpers (dev.lua, probe.lua) are left out.
# Usage: package.ps1 -Version 0.2
param([Parameter(Mandatory)] [string] $Version)
$root = Split-Path $PSScriptRoot -Parent
# Players of different versions are kept apart by Coop.VERSION (lobby check): it must be this one.
$luaVersion = (Select-String -Path (Join-Path $root "lua\coop.lua") -Pattern '^Coop.VERSION = "([^"]+)"').Matches[0].Groups[1].Value
if ($luaVersion -ne $Version) { throw "lua\coop.lua has Coop.VERSION = $luaVersion, not $Version" }
$dll = Join-Path $root "native\build\dinput8.dll"
if (-not (Test-Path $dll)) { throw "build native\build\dinput8.dll first (sh native/build.sh)" }
$stage = Join-Path $root "dist\jericho-coop-$Version"
$files = Join-Path $stage "files"
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $files "bin"), (Join-Path $files "coop") | Out-Null
Copy-Item $dll (Join-Path $files "bin")
$steam = Join-Path $root "..\..\..	ools\steam\steam_api.dll"
$steamSha = "FDAFB7C65EC7D4182B42BF92CC8671C68E4DC547CC6E613899D2618A47EB65DA"
if (-not (Test-Path $steam)) { throw "tools\steam\steam_api.dll missing (Steamworks.NET Standalone 2025.164.1, Windows-x86)" }
if ((Get-FileHash $steam -Algorithm SHA256).Hash -ne $steamSha) { throw "tools\steam\steam_api.dll is not the pinned one" }
Copy-Item $steam (Join-Path $files "coop")
Get-ChildItem (Join-Path $root "lua\*.lua") | Where-Object { $_.Name -notin "dev.lua", "probe.lua" } |
    Copy-Item -Destination (Join-Path $files "coop")
Set-Content -Path (Join-Path $files "coop\version.txt") -Value $Version -Encoding ASCII
# The animation builder the installer runs for the experimental "own eyes" cutscene view.
New-Item -ItemType Directory -Force (Join-Path $files "coop\anims") | Out-Null
Copy-Item (Join-Path $PSScriptRoot "cm3_retarget.py"), (Join-Path $PSScriptRoot "bfpk.py"), (Join-Path $PSScriptRoot "m3d.py") (Join-Path $files "coop\anims")
# Installer
Copy-Item (Join-Path $root "tools\installer.ps1") (Join-Path $stage "coop-installer.ps1")
Set-Content -Path (Join-Path $stage "Install Co-op.bat") -Encoding ASCII `
    -Value '@powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0coop-installer.ps1" %*'
Copy-Item (Join-Path $root "docs\release-readme.txt") (Join-Path $stage "README-COOP.txt")
Copy-Item (Join-Path $root "LICENSE") (Join-Path $stage "LICENSE.txt")
Copy-Item (Join-Path $root "docs\enet-license.txt") (Join-Path $stage "ENET-LICENSE.txt")
Copy-Item (Join-Path $root "docs\steam-notice.txt") (Join-Path $stage "STEAM-NOTICE.txt")
$zip = Join-Path $root "dist\jericho-coop-$Version.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
Remove-Item $stage -Recurse -Force
"packaged $zip"

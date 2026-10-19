# Build the release archive: dist\jericho-coop-<version>.zip, laid out like the game folder
# (bin\dinput8.dll, coop\*.lua) plus the player's readme and the licenses. Run native\build.sh
# first. The test helpers (dev.lua) are left out.
# Usage: package.ps1 -Version 0.1.0
param([Parameter(Mandatory)] [string] $Version)
$root = Split-Path $PSScriptRoot -Parent
$dll = Join-Path $root "native\build\dinput8.dll"
if (-not (Test-Path $dll)) { throw "build native\build\dinput8.dll first (sh native/build.sh)" }
$stage = Join-Path $root "dist\jericho-coop-$Version"
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $stage "bin"), (Join-Path $stage "coop") | Out-Null
Copy-Item $dll (Join-Path $stage "bin")
Get-ChildItem (Join-Path $root "lua\*.lua") | Where-Object Name -ne "dev.lua" |
    Copy-Item -Destination (Join-Path $stage "coop")
Copy-Item (Join-Path $root "docs\release-readme.txt") (Join-Path $stage "README-COOP.txt")
Copy-Item (Join-Path $root "LICENSE") (Join-Path $stage "LICENSE.txt")
Copy-Item (Join-Path $root "docs\enet-license.txt") (Join-Path $stage "ENET-LICENSE.txt")
$zip = Join-Path $root "dist\jericho-coop-$Version.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
Remove-Item $stage -Recurse -Force
"packaged $zip"

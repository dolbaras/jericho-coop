# Build the release archive dist\jericho-coop-<version>.zip:
#   Install Co-op.bat + coop-installer.ps1   the installer (backs up what it replaces, uninstalls)
#   files\                                   what goes into the game folder (bin\dinput8.dll,
#                                            coop\*.lua, the cutscene animation builder)
#   README-COOP.txt, LICENSE.txt, ENET-LICENSE.txt
# Run native\build.sh first. The test helpers (dev.lua, probe.lua) are left out.
# Usage: package.ps1 -Version 0.1.1
param([Parameter(Mandatory)] [string] $Version)
$root = Split-Path $PSScriptRoot -Parent
$dll = Join-Path $root "native\build\dinput8.dll"
if (-not (Test-Path $dll)) { throw "build native\build\dinput8.dll first (sh native/build.sh)" }
$stage = Join-Path $root "dist\jericho-coop-$Version"
$files = Join-Path $stage "files"
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $files "bin"), (Join-Path $files "coop") | Out-Null
Copy-Item $dll (Join-Path $files "bin")
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
$zip = Join-Path $root "dist\jericho-coop-$Version.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
Remove-Item $stage -Recurse -Force
"packaged $zip"

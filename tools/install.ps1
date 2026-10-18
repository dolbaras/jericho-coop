# Install the co-op mod into a game folder: <game>\bin\dinput8.dll and <game>\coop\*.lua.
# Backs up an existing dinput8.dll that is not ours. Usage: install.ps1 -Game <game dir>
param([Parameter(Mandatory)] [string] $Game)
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
"installed to $Game"

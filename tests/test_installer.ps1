# Offline tests of the players' installer with other mods' files in the game folder: an Ultimate ASI Loader (or another mod's
# DLL) as bin\dinput8.dll, the other proxy DLLs mods use (d3d9, dsound, version, xinput1_3, winmm), plugin folders; install,
# reinstall, update (what the shortcut's launcher runs: coop-installer.ps1 -Game <folder> -NoShortcut, here -Quiet), uninstall.
# Everything happens on stand-in game folders under %TEMP% (a text file for bin\Jericho.exe; the DLLs are made-up PE files that
# are only read, never loaded); no game, no network, nothing outside the temp folder.
# -Zip <release zip>: tests that package instead of one built from this tree (the published 0.3.1 fails the new cases).
# -OldZip <release zip>: also that release installed over an ASI loader and then updated by this tree's installer.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_installer.ps1 [-Zip <zip>] [-OldZip <zip>] [-Keep]
param([string] $Zip = "", [string] $OldZip = "", [switch] $Keep)
$ErrorActionPreference = "Stop"
$env:PSModulePath = (($env:PSModulePath -split ";") | Where-Object { $_ -notlike "*\PowerShell\*" }) -join ";"   # Windows PowerShell 5.1 modules only
foreach ($z in "Zip", "OldZip") {
    $v = Get-Variable $z -ValueOnly
    if ($v) { if (-not (Test-Path -LiteralPath $v -PathType Leaf)) { throw "-${z}: $v not found" }; Set-Variable $z (Resolve-Path -LiteralPath $v).Path }
}
$root = Split-Path $PSScriptRoot -Parent
$base = Join-Path ([IO.Path]::GetTempPath()) ("jericho-installer-test-" + $PID)
Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $base | Out-Null
$script:fails = 0; $script:checks = 0
function Check($cond, $name) { $script:checks++; if ($cond) { Write-Host "ok   $name" } else { Write-Host "FAIL $name"; $script:fails++ } }
function Sha($p) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return "(missing)" }; $fs = [IO.File]::OpenRead($p); try { [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($fs)) -replace "-", "" } finally { $fs.Close() } }
function Snap($dir) {
    $t = @{}
    foreach ($f in Get-ChildItem -LiteralPath $dir -Recurse -File -Force) { $t[$f.FullName.Substring($dir.Length + 1)] = Sha $f.FullName }
    $t
}
function Snap-Diff($a, $b) {   # (not "Diff": an alias of Compare-Object in Windows PowerShell)
    @($a.Keys | Where-Object { -not $b.ContainsKey($_) -or $a[$_] -ne $b[$_] }) + @($b.Keys | Where-Object { -not $a.ContainsKey($_) }) | Sort-Object -Unique
}
function Run-PS([string] $script, [string[]] $a) {
    $o = Join-Path $base "out.txt"; $e = Join-Path $base "err.txt"
    Remove-Item $o, $e -ErrorAction SilentlyContinue
    $p = Start-Process powershell -ArgumentList (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$script`"") + $a) -Wait -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $o -RedirectStandardError $e
    $script:exit = $p.ExitCode
    $script:out = (Get-Content -LiteralPath $o -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $e -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
}
function Rec($g) { @(Get-Content -LiteralPath (Join-Path $g "coop\install.txt") -ErrorAction SilentlyContinue) }

# 1. the package: built from this tree (tools\package.ps1 into the temp folder) unless -Zip
if (-not $Zip) {
    $ver = (Select-String -Path (Join-Path $root "lua\coop.lua") -Pattern '^Coop.VERSION = "([^"]+)"').Matches[0].Groups[1].Value
    # (the workspace's shared bug-report collector: the first tools\log-collector above the repository)
    $lc = $null
    for ($d = Split-Path $root -Parent; $d -and -not $lc; $d = Split-Path $d -Parent) { if (Test-Path -LiteralPath (Join-Path $d "tools\log-collector\collect-logs.ps1")) { $lc = Join-Path $d "tools\log-collector" } }
    $dist = Join-Path $base "dist"
    $pkgOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\package.ps1") -Version $ver -Dist $dist -LogCollector $lc 2>&1
    if ($LASTEXITCODE) { throw "package.ps1 failed: $pkgOut" }
    $Zip = Join-Path $dist "jericho-coop-$ver.zip"
}
Write-Host "package: $Zip"
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$za = [IO.Compression.ZipFile]::OpenRead($Zip)
try { $en = @($za.Entries | ForEach-Object FullName) } finally { $za.Dispose() }
$bs = @($en | Where-Object { $_.Contains('\') })
Check ($en.Count -ge 20 -and $bs.Count -eq 0 -and ($en -contains "files/bin/dinput8.dll") -and ($en -contains "coop-installer.ps1")) "the zip's $($en.Count) entry names use '/' ($($bs.Count) with '\'$(if ($bs.Count) { ': ' + $bs[0] }))"
$x1 = Join-Path $base "x1"; $x2 = Join-Path $base "x2"
[IO.Compression.ZipFile]::ExtractToDirectory($Zip, $x1)
# x2: the same package as a later version (what an update brings)
Copy-Item -LiteralPath $x1 $x2 -Recurse
Set-Content -LiteralPath (Join-Path $x2 "files\coop\version.txt") -Value "9.9.9" -Encoding ASCII
$ourDll = Sha (Join-Path $x1 "files\bin\dinput8.dll")

# 2. stand-in game folders. New-FakePe: a minimal PE with an export table of these names (never loaded; the installer reads it).
function New-FakePe($path, [string[]] $exports, [int] $machine = 0x14C, [string] $extra = "") {
    $b = New-Object byte[] 0xA00
    $w16 = { param($o, $v) $b[$o] = [byte]($v -band 0xFF); $b[$o + 1] = [byte](($v -shr 8) -band 0xFF) }
    $w32 = { param($o, [long] $v) & $w16 $o ($v -band 0xFFFF); & $w16 ($o + 2) (($v -shr 16) -band 0xFFFF) }
    $b[0] = 0x4D; $b[1] = 0x5A; & $w32 0x3C 0x80
    $b[0x80] = 0x50; $b[0x81] = 0x45
    $pe64 = $machine -eq 0x8664
    & $w16 0x84 $machine; & $w16 0x86 2; $optsize = $(if ($pe64) { 0xF0 } else { 0xE0 }); & $w16 0x94 $optsize; & $w16 0x96 0x2102
    $opt = 0x98; & $w16 $opt $(if ($pe64) { 0x20B } else { 0x10B })
    $dirs = $opt + $(if ($pe64) { 112 } else { 96 }); & $w32 ($dirs - 4) 16; & $w32 $dirs 0x2000; & $w32 ($dirs + 4) 0x100
    $sec = $opt + $optsize
    [Text.Encoding]::ASCII.GetBytes(".text").CopyTo($b, $sec); & $w32 ($sec + 8) 0x200; & $w32 ($sec + 12) 0x1000; & $w32 ($sec + 16) 0x200; & $w32 ($sec + 20) 0x400
    [Text.Encoding]::ASCII.GetBytes(".edata").CopyTo($b, $sec + 40); & $w32 ($sec + 48) 0x400; & $w32 ($sec + 52) 0x2000; & $w32 ($sec + 56) 0x400; & $w32 ($sec + 60) 0x600
    & $w32 (0x600 + 20) $exports.Count; & $w32 (0x600 + 24) $exports.Count; & $w32 (0x600 + 32) 0x2040
    $str = 0x100
    for ($i = 0; $i -lt $exports.Count; $i++) {
        & $w32 (0x640 + 4 * $i) (0x2000 + $str)
        [Text.Encoding]::ASCII.GetBytes($exports[$i]).CopyTo($b, 0x600 + $str); $str += $exports[$i].Length + 1
    }
    if ($extra) { [Text.Encoding]::ASCII.GetBytes($extra).CopyTo($b, 0x480) }
    New-Item -ItemType Directory -Force (Split-Path $path -Parent) | Out-Null
    [IO.File]::WriteAllBytes($path, $b)
}
# (the loader's exports as v10.0.2 / v7.8.0 have them, a few of each: dinput8's, winmm's, msvfw32's, its own)
$ualExports = @("DirectInput8Create", "DrawDibDraw", "IsUltimateASILoader", "timeBeginPeriod", "timeGetTime")
$script:n = 0
# A game folder: bin\Jericho.exe (text), another mod's Pack1.packed (the animation build leaves it alone: no Python run), game data.
# -Ual: an ASI loader as bin\dinput8.dll + bin\dinput8.ini + bin\scripts\*.asi + bin\plugins\*.asi. -Proxies: d3d9 / dsound (+ini) /
# version / xinput1_3 of other mods. -Winmm: a winmm.dll of someone else's in bin.
function New-Game([switch] $Ual, [int] $Machine = 0x14C, [switch] $NoIni, [switch] $Proxies, [switch] $Winmm, [string] $Dinput8Text = "") {
    $script:n++
    $g = Join-Path $base ("game $($script:n) - Clive Barker's Jericho")
    New-Item -ItemType Directory -Force (Join-Path $g "bin") | Out-Null
    [IO.File]::WriteAllText((Join-Path $g "bin\Jericho.exe"), "stand-in exe, never run")
    [IO.File]::WriteAllText((Join-Path $g "Pack1.packed"), "another mod's Pack1.packed")
    [IO.File]::WriteAllText((Join-Path $g "Data00.packed"), "game data stand-in")
    if ($Ual) {
        New-FakePe (Join-Path $g "bin\dinput8.dll") $ualExports $Machine "Ultimate ASI Loader stand-in $($script:n)"
        if (-not $NoIni) { Set-Content -LiteralPath (Join-Path $g "bin\dinput8.ini") -Value "[GlobalSets]`r`nLoadPlugins=1" -Encoding ASCII }
        New-FakePe (Join-Path $g "bin\scripts\Jericho.WidescreenFix.asi") @("InitializeASI") 0x14C "IsUltimateASILoader"
        Set-Content -LiteralPath (Join-Path $g "bin\scripts\Jericho.WidescreenFix.ini") -Value "[MAIN]`r`nFOVFactor = 1.2" -Encoding ASCII
        New-FakePe (Join-Path $g "bin\plugins\FpsLimit.asi") @("InitializeASI") 0x14C ""
    }
    if ($Dinput8Text) { [IO.File]::WriteAllText((Join-Path $g "bin\dinput8.dll"), $Dinput8Text) }
    if ($Proxies) {
        New-FakePe (Join-Path $g "bin\d3d9.dll") @("Direct3DCreate9", "Direct3DCreate9Ex") 0x14C "DXVK stand-in"
        New-FakePe (Join-Path $g "bin\dsound.dll") @("DirectSoundCreate", "DirectSoundCreate8") 0x14C "IndirectSound stand-in"
        Set-Content -LiteralPath (Join-Path $g "bin\dsound.ini") -Value "[IndirectSound]`r`nhardwareBufferCount=128" -Encoding ASCII
        New-FakePe (Join-Path $g "bin\version.dll") @("GetFileVersionInfoA", "VerQueryValueA") 0x14C "version proxy stand-in"
        New-FakePe (Join-Path $g "bin\xinput1_3.dll") @("XInputGetState", "XInputSetState") 0x14C "xinput proxy stand-in"
    }
    if ($Winmm) { New-FakePe (Join-Path $g "bin\winmm.dll") @("timeGetTime", "PlaySoundA") 0x14C "a winmm.dll of someone else's" }
    $g
}
function Install($x, $g, [string[]] $more = @()) { Run-PS (Join-Path $x "coop-installer.ps1") (@("-Quiet", "-Game", "`"$g`"", "-ShortcutDir", "`"$(Join-Path $base 'links')`"", "-Lang", "en") + $more) }
# the update as the launcher runs it (the new version's installer, -NoShortcut), quiet
function Update($x, $g) { Install $x $g @("-NoShortcut") }
function Uninstall($g) { Run-PS (Join-Path $g "coop-installer.ps1") @("-Quiet", "-Uninstall", "-Game", "`"$g`"", "-Lang", "en") }
New-Item -ItemType Directory -Force (Join-Path $base "links") | Out-Null
# (the English texts of the package under test, read from its installer)
$tok = $null; $perr = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $x1 "coop-installer.ps1"), [ref]$tok, [ref]$perr)
$asg = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:TEXTS' }, $true)
$TX = & ([ScriptBlock]::Create($asg.Right.Extent.Text))
function T($k) { $v = $TX["en"][$k]; if ($v) { $v -replace '`n', "`n" } else { "<no text $k>" } }

# 3. an Ultimate ASI Loader as bin\dinput8.dll, next to the other proxies and plugin folders
$g = New-Game -Ual -Proxies
$clean = Snap $g
Install $x1 $g
$rec = Rec $g
Check ($script:exit -eq 0 -and (Sha (Join-Path $g "bin\dinput8.dll")) -eq $ourDll) "ASI loader: install exit 0, bin\dinput8.dll is the mod's ($($script:exit))"
Check ((Test-Path -LiteralPath (Join-Path $g "coop-backup\bin\dinput8.dll")) -and (Sha (Join-Path $g "coop-backup\bin\dinput8.dll")) -eq $clean["bin\dinput8.dll"]) "ASI loader: the original is kept in coop-backup"
Check ((Test-Path -LiteralPath (Join-Path $g "bin\winmm.dll")) -and (Sha (Join-Path $g "bin\winmm.dll")) -eq $clean["bin\dinput8.dll"]) "ASI loader: it also runs on as bin\winmm.dll (the same bytes), so its plugins load"
Check ((Test-Path -LiteralPath (Join-Path $g "bin\winmm.ini")) -and (Sha (Join-Path $g "bin\winmm.ini")) -eq $clean["bin\dinput8.ini"]) "ASI loader: its settings bin\dinput8.ini go along as bin\winmm.ini"
Check (($rec -contains "chain=bin\winmm.dll") -and ($rec -contains "chain=bin\winmm.ini") -and ($rec -contains "file=bin\winmm.dll") -and ($rec -contains "file=bin\winmm.ini") -and ($rec -contains "backup=bin\dinput8.dll")) "ASI loader: the record lists the copies (chain= and file=) and the backup"
Check ($script:out.Contains((T "asi_note"))) "ASI loader: the result says it runs on as bin\winmm.dll"
$after = Snap $g
$changed = @(Snap-Diff $clean $after | Where-Object { $clean.ContainsKey($_) -and $_ -ne "bin\dinput8.dll" })
Check ($changed.Count -eq 0) "ASI loader: every other file unchanged: plugins (bin\scripts, bin\plugins), d3d9 / dsound (+ini) / version / xinput1_3 ($($changed -join ', '))"
Install $x1 $g
Update $x2 $g
$rec = Rec $g
Check ($script:exit -eq 0 -and (Get-Content -LiteralPath (Join-Path $g "coop\version.txt") -TotalCount 1) -eq "9.9.9" -and (Sha (Join-Path $g "bin\winmm.dll")) -eq $clean["bin\dinput8.dll"] -and
       (Sha (Join-Path $g "coop-backup\bin\dinput8.dll")) -eq $clean["bin\dinput8.dll"] -and (Sha (Join-Path $g "bin\dinput8.dll")) -eq $ourDll) "ASI loader: reinstall + update keep the backup and the copy"
Check (@($rec | Where-Object { $_ -eq "chain=bin\winmm.dll" }).Count -eq 1 -and @($rec | Where-Object { $_ -eq "file=bin\winmm.dll" }).Count -eq 1 -and
       @($rec | Where-Object { $_ -eq "backup=bin\dinput8.dll" }).Count -eq 1) "ASI loader: after reinstall + update each line once"
Uninstall $g
$d = @(Snap-Diff $clean (Snap $g))
Check ($script:exit -eq 0 -and $d.Count -eq 0) "ASI loader: uninstall puts the folder back byte for byte (the loader as bin\dinput8.dll, no winmm.dll / .ini; $($d -join ', '))"

# 4. the player changed the copy (another winmm.dll) while co-op was installed: the uninstall leaves it
$g = New-Game -Ual
$clean = Snap $g
Install $x1 $g
[IO.File]::WriteAllText((Join-Path $g "bin\winmm.dll"), "the player's own winmm.dll now")
Uninstall $g
Check ($script:exit -eq 0 -and (Get-Content -LiteralPath (Join-Path $g "bin\winmm.dll") -Raw) -eq "the player's own winmm.dll now" -and
       (Sha (Join-Path $g "bin\dinput8.dll")) -eq $clean["bin\dinput8.dll"] -and -not (Test-Path -LiteralPath (Join-Path $g "bin\winmm.ini")) -and
       -not (Test-Path -LiteralPath (Join-Path $g "coop-backup"))) "a winmm.dll the player changed stays; the loader comes back; winmm.ini goes"

# 5. cases where no copy is made: a loader next to a foreign winmm.dll, a 64-bit loader, another mod's DLL that is no loader, a
#    plugin that only names the loader; and a loader without dinput8.ini (the DLL only)
foreach ($c in @(@{ name = "loader + a foreign winmm.dll"; g = (New-Game -Ual -Winmm) }, @{ name = "a 64-bit loader"; g = (New-Game -Ual -Machine 0x8664) },
                 @{ name = "a dinput8.dll that is no loader"; g = (New-Game -Dinput8Text "another mod's dinput8.dll") },
                 @{ name = "a DLL that only names IsUltimateASILoader"; g = (New-Game) })) {
    $g = $c.g
    if ($c.name -like "*only names*") { New-FakePe (Join-Path $g "bin\dinput8.dll") @("DirectInput8Create", "timeGetTime") 0x14C "IsUltimateASILoader" }
    $cl = Snap $g
    $w0 = if ($cl.ContainsKey("bin\winmm.dll")) { $cl["bin\winmm.dll"] } else { "" }
    Install $x1 $g
    $rec = Rec $g
    $w1 = if (Test-Path -LiteralPath (Join-Path $g "bin\winmm.dll")) { Sha (Join-Path $g "bin\winmm.dll") } else { "" }
    Check ($script:exit -eq 0 -and $w1 -eq $w0 -and -not ($rec | Where-Object { $_ -like "chain=*" }) -and (Sha (Join-Path $g "coop-backup\bin\dinput8.dll")) -eq $cl["bin\dinput8.dll"]) "$($c.name): kept in coop-backup, no copy, no chain= line"
    Check ($script:out.Contains((T "off_note"))) "$($c.name): the result says it is kept and off"
    Uninstall $g
    $d = @(Snap-Diff $cl (Snap $g))
    Check ($script:exit -eq 0 -and $d.Count -eq 0) "$($c.name): uninstall leaves the folder byte for byte ($($d -join ', '))"
}
$g = New-Game -Ual -NoIni
$clean = Snap $g
Install $x1 $g
$rec = Rec $g
Check ((Sha (Join-Path $g "bin\winmm.dll")) -eq $clean["bin\dinput8.dll"] -and -not (Test-Path -LiteralPath (Join-Path $g "bin\winmm.ini")) -and ($rec -contains "chain=bin\winmm.dll") -and -not ($rec -contains "chain=bin\winmm.ini")) "a loader without dinput8.ini: winmm.dll only"
Uninstall $g
Check ((@(Snap-Diff $clean (Snap $g))).Count -eq 0) "a loader without dinput8.ini: uninstall leaves the folder byte for byte"

# 6. a game without any dinput8.dll, other proxies only: nothing of theirs is touched, nothing chained, no note
$g = New-Game -Proxies
$clean = Snap $g
Install $x1 $g
$rec = Rec $g
Check ($script:exit -eq 0 -and -not ($rec | Where-Object { $_ -like "chain=*" -or $_ -like "backup=*" }) -and -not $script:out.Contains((T "off_note")) -and -not (Test-Path -LiteralPath (Join-Path $g "coop-backup"))) "no dinput8.dll: no backup, no copy, no note"
Uninstall $g
$d = @(Snap-Diff $clean (Snap $g))
Check ($script:exit -eq 0 -and $d.Count -eq 0) "no dinput8.dll, other proxies: uninstall byte for byte ($($d -join ', '))"

# 7. another mod's dinput8.dll put OVER the co-op one after the install (the player installed an ASI mod later)
#    a) uninstall then: that DLL stays (it is the player's now); everything of co-op goes
$g = New-Game -Proxies
$clean = Snap $g
Install $x1 $g
New-FakePe (Join-Path $g "bin\dinput8.dll") $ualExports 0x14C "a loader the player put over co-op"
$f1 = Sha (Join-Path $g "bin\dinput8.dll")
Uninstall $g
$d = @(Snap-Diff $clean (Snap $g))
Check ($script:exit -eq 0 -and (Test-Path -LiteralPath (Join-Path $g "bin\dinput8.dll")) -and (Sha (Join-Path $g "bin\dinput8.dll")) -eq $f1) "over co-op's DLL, then uninstall: the other mod's dinput8.dll stays in place"
Check (($d -join ",") -eq "bin\dinput8.dll") "over co-op's DLL, then uninstall: nothing else of co-op is left ($($d -join ', '))"
Check ($script:out.Contains((T "left_note").Trim())) "over co-op's DLL, then uninstall: the result says it stays"
#    b) an update then (the shortcut's launcher found a newer release): it is kept as the original, its copy as winmm.dll made; the
#       uninstall afterwards puts it back
$g = New-Game -Proxies
$clean = Snap $g
Install $x1 $g
New-FakePe (Join-Path $g "bin\dinput8.dll") $ualExports 0x14C "a loader the player put over co-op"
Set-Content -LiteralPath (Join-Path $g "bin\dinput8.ini") -Value "[GlobalSets]`r`nLoadPlugins=1" -Encoding ASCII
$f1 = Sha (Join-Path $g "bin\dinput8.dll")
Update $x2 $g
$rec = Rec $g
Check ($script:exit -eq 0 -and (Test-Path -LiteralPath (Join-Path $g "coop-backup\bin\dinput8.dll")) -and (Sha (Join-Path $g "coop-backup\bin\dinput8.dll")) -eq $f1 -and ($rec -contains "backup=bin\dinput8.dll")) "over co-op's DLL, then update: it is kept in coop-backup (not overwritten unseen)"
Check ((Sha (Join-Path $g "bin\dinput8.dll")) -eq $ourDll -and (Test-Path -LiteralPath (Join-Path $g "bin\winmm.dll")) -and (Sha (Join-Path $g "bin\winmm.dll")) -eq $f1) "over co-op's DLL, then update: co-op's DLL back, the loader runs on as winmm.dll"
Uninstall $g
$d = @(Snap-Diff $clean (Snap $g))
Check ($script:exit -eq 0 -and (Sha (Join-Path $g "bin\dinput8.dll")) -eq $f1 -and -not (Test-Path -LiteralPath (Join-Path $g "bin\winmm.dll")) -and (($d | Where-Object { $_ -notin "bin\dinput8.dll", "bin\dinput8.ini" }).Count -eq 0)) "over co-op's DLL, update, uninstall: the player's loader is back as dinput8.dll, nothing of co-op left ($($d -join ', '))"
#    c) the same over a game that had a loader before co-op: the newer one wins, the copy of the older one is replaced
$g = New-Game -Ual
$clean = Snap $g
Install $x1 $g
New-FakePe (Join-Path $g "bin\dinput8.dll") $ualExports 0x14C "a NEWER loader the player put over co-op"
$f2 = Sha (Join-Path $g "bin\dinput8.dll")
Update $x2 $g
Check ($script:exit -eq 0 -and (Sha (Join-Path $g "coop-backup\bin\dinput8.dll")) -eq $f2 -and (Sha (Join-Path $g "bin\winmm.dll")) -eq $f2 -and (Sha (Join-Path $g "bin\dinput8.dll")) -eq $ourDll) "a newer loader over co-op's DLL, then update: it is the original now and runs as winmm.dll"
Uninstall $g
$d = @(Snap-Diff $clean (Snap $g))
Check ($script:exit -eq 0 -and (Sha (Join-Path $g "bin\dinput8.dll")) -eq $f2 -and -not (Test-Path -LiteralPath (Join-Path $g "bin\winmm.dll")) -and ($d -join ",") -eq "bin\dinput8.dll") "a newer loader, update, uninstall: the newer loader stays as dinput8.dll, the rest as before co-op ($($d -join ', '))"

# 8. -OldZip: that release installed over an ASI loader (kept off), then this package's installer as the launcher runs it
if ($OldZip) {
    $xo = Join-Path $base "xold"
    [IO.Compression.ZipFile]::ExtractToDirectory($OldZip, $xo)
    $g = New-Game -Ual
    $clean = Snap $g
    Install $xo $g
    $oldOk = $script:exit -eq 0
    Check ($oldOk -and (Sha (Join-Path $g "coop-backup\bin\dinput8.dll")) -eq $clean["bin\dinput8.dll"]) "old release over an ASI loader: kept in coop-backup (winmm.dll made: $(Test-Path -LiteralPath (Join-Path $g 'bin\winmm.dll')))"
    Update $x2 $g
    $rec = Rec $g
    Check ($script:exit -eq 0 -and (Sha (Join-Path $g "bin\winmm.dll")) -eq $clean["bin\dinput8.dll"] -and ($rec -contains "chain=bin\winmm.dll") -and (Sha (Join-Path $g "coop-backup\bin\dinput8.dll")) -eq $clean["bin\dinput8.dll"]) "the update from the old release makes the kept loader run on as winmm.dll"
    Uninstall $g
    $d = @(Snap-Diff $clean (Snap $g))
    Check ($script:exit -eq 0 -and $d.Count -eq 0) "old release + update + uninstall: byte for byte ($($d -join ', '))"
}

# 9. texts: the new keys in all six languages, translated; the result text fits its label (measured, no window)
$langs = "en", "ru", "de", "fr", "es", "it"
$newKeys = "asi_copy", "asi_note", "off_note", "winmm_taken", "left_alone", "foreign_over_coop", "left_in_place", "left_note"
foreach ($lg in $langs) {
    $missing = @($newKeys | Where-Object { -not $TX[$lg][$_] })
    Check ($missing.Count -eq 0) "texts $lg : the dinput8.dll keys are there ($($missing -join ','))"
    if ($lg -ne "en") {
        $same = @($newKeys | Where-Object { $TX[$lg][$_] -and $TX[$lg][$_] -eq $TX["en"][$_] })
        Check ($same.Count -eq 0) "texts $lg : translated ($($same -join ','))"
    }
}
# Fit-Result's rooms at 96 DPI (the label at y 66 of the work page): 160 px, 210 without the progress bar, 290 without the log
# (success); then Segoe UI 10.5 -> 10 -> 9.5 -> 9 -> 8.5. The longest result: SMOD + the failed animation build + the loader note.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$tall = @()
foreach ($lg in $langs) {
    $t = $TX[$lg]
    if (-not $t["asi_note"]) { $tall += "$lg (no note)"; continue }
    $txt = ($t["start_the_game_the"] + "`n`n" + $t["the_shortcut"] + $t["smod_found_supported"] + "`n`n" + $t["the_build_of_the"] + " " + $t["the_cutscene_animations_and"] + "`n`n" + $t["asi_note"]) -replace '`n', "`n"
    $fits = $false
    foreach ($sz in 10.5, 10, 9.5, 9, 8.5) {
        $h = [Windows.Forms.TextRenderer]::MeasureText($txt, (New-Object Drawing.Font("Segoe UI", $sz)), (New-Object Drawing.Size(540, 100000)), [Windows.Forms.TextFormatFlags]::WordBreak).Height
        if ($h -le 290) { $fits = $true; break }
    }
    if (-not $fits) { $tall += "$lg $h px" }
    foreach ($k in "asi_note", "off_note") {
        $one = ($t["start_the_game_the"] + "`n`n" + $t["the_shortcut"] + $t["smod_found_supported"] + "`n`n" + $t[$k]) -replace '`n', "`n"
        $h = [Windows.Forms.TextRenderer]::MeasureText($one, (New-Object Drawing.Font("Segoe UI", 10.5)), (New-Object Drawing.Size(540, 100000)), [Windows.Forms.TextFormatFlags]::WordBreak).Height
        if ($h -gt 210) { $tall += "$lg/$k $h px at 10.5" }
    }
}
Check ($tall.Count -eq 0) "the result text with the dinput8.dll note fits (at 10.5 pt in 210 px; with the animation failure too at >= 8.5 pt in 290 px) ($($tall -join ', '))"
$inst = Get-Content -LiteralPath (Join-Path $x1 "coop-installer.ps1") -Raw -Encoding UTF8
Check ($inst.Contains("function Fit-Result") -and $inst.Contains("Fit-Result `$ok")) "the result page fits its text (Fit-Result)"

Write-Host ""
Write-Host "test_installer: $($script:checks - $script:fails)/$($script:checks) passed"
if (-not $Keep) { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Host "kept: $base" }
exit $(if ($script:fails) { 1 } else { 0 })

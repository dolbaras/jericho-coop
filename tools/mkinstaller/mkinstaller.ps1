# Builds a single-file Windows setup exe from a release zip (game independent).
#
#   powershell -File mkinstaller.ps1 -Zip dist\x-coop-1.2.3.zip -Out dist\x-coop-setup-1.2.3.exe `
#       -Product "X Co-op" -Version 1.2.3 [-Icon app.ico | -Accent 227cce] [-TempPrefix x-coop-setup]
#
# The exe is stub.c (this folder, built with the workspace's zig: zig cc -target x86-windows-gnu, windows subsystem, no
# console) with the zip embedded as a resource (RCDATA 1) next to a small config (RCDATA 2: product, temp folder prefix,
# the installer script's name in the zip, the zip's SHA-256), an icon, VERSIONINFO and a manifest (asInvoker, DPI aware,
# supported OS list, long paths). At run time it checks the SHA-256, unpacks the zip into a fresh %TEMP% folder, runs the
# zip's PowerShell installer from there with the options it got, returns its exit code and deletes the folder.
# The zip is embedded as it is (the zip stays the auto-update asset, the exe is an extra download); the exe is unsigned.
#
# After the build it unpacks the exe's payload with `--extract` and compares every file with the zip (names, sizes, SHA-256);
# -NoSelfTest skips that.
param([Parameter(Mandatory)] [string] $Zip,
      [Parameter(Mandatory)] [string] $Out,
      [Parameter(Mandatory)] [string] $Product,
      [Parameter(Mandatory)] [string] $Version,
      [string] $Description = "",
      [string] $Icon = "",
      [string] $Accent = "227cce",
      [string] $TempPrefix = "",
      [string] $Installer = "coop-installer.ps1",
      [string] $Zig = "",
      [string[]] $CFlags = @(),   # extra compiler flags (tests: -DFORCE_LANG=<0..5>)
      [switch] $NoSelfTest)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Sha256($p) {
    $fs = [IO.File]::OpenRead($p)
    try { ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($fs)) -replace "-", "").ToLower() } finally { $fs.Close() }
}
if (-not $Zig) { $Zig = if ($env:ZIG) { $env:ZIG } else { Join-Path $PSScriptRoot "..\zig\zig-x86_64-windows-0.16.0\zig.exe" } }
if (-not (Test-Path -LiteralPath $Zig)) { throw "zig not found: $Zig (set ZIG or -Zig)" }
$Zip = (Resolve-Path -LiteralPath $Zip).Path
if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)') { throw "version must start with major.minor.patch: $Version" }
$v4 = "$($Matches[1]),$($Matches[2]),$($Matches[3]),0"; $v4dot = "$($Matches[1]).$($Matches[2]).$($Matches[3]).0"
if (-not $Description) { $Description = "$Product setup" }
if (-not $TempPrefix) { $TempPrefix = (($Product.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')) + "-setup" }
if ($TempPrefix -notmatch '^[a-z0-9-]+$') { throw "TempPrefix: lower-case letters, digits, '-' only" }
foreach ($t in $Product, $Description) { if ($t -match '["\\\r\n]') { throw "no quotes, backslashes or line breaks in the product or description" } }

# The zip: the installer is in it, nothing is encrypted, zip64 or named in a way the stub refuses.
$z = [IO.Compression.ZipFile]::OpenRead($Zip)
try {
    if (-not $z.GetEntry($Installer)) { throw "$Installer is not at the root of $Zip" }
    foreach ($e in $z.Entries) {
        if ($e.FullName -match '(^|[/\\])\.\.([/\\]|$)|:|^[/\\]') { throw "the stub refuses the zip entry name: $($e.FullName)" }
        if ($e.Length -ge 1GB) { throw "zip entry too big for the stub: $($e.FullName)" }
    }
    if ($z.Entries.Count -ge 65535) { throw "zip64 is not supported by the stub" }
} finally { $z.Dispose() }

$work = Join-Path ([IO.Path]::GetTempPath()) ("mkinstaller-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory $work | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "stub.c") (Join-Path $work "stub.c")
    Copy-Item -LiteralPath $Zip (Join-Path $work "payload.zip")
    if ($Icon) { Copy-Item -LiteralPath $Icon (Join-Path $work "app.ico") }
    else { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "make_icon.ps1") -Out (Join-Path $work "app.ico") -Accent $Accent | Out-Null; if ($LASTEXITCODE) { throw "make_icon.ps1 failed" } }
    $zipSha = Sha256 $Zip
    [IO.File]::WriteAllText((Join-Path $work "config.txt"), "product=$Product`nprefix=$TempPrefix`ninstaller=$Installer`nsha256=$zipSha`n", (New-Object Text.UTF8Encoding($false)))
    $manifest = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity type="win32" name="CoopSetup.$TempPrefix" version="$v4dot" processorArchitecture="*"/>
  <description>$Description</description>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security><requestedPrivileges><requestedExecutionLevel level="asInvoker" uiAccess="false"/></requestedPrivileges></security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{e2011457-1546-43c5-a5fe-008deee3d3f0}"/>
      <supportedOS Id="{35138b9a-5d96-4fbd-8e2d-a2440225f93a}"/>
      <supportedOS Id="{4a2f28e3-53b9-4441-ba9c-d69d4a4a6e38}"/>
      <supportedOS Id="{1f676c76-80e1-4239-95bb-83d0f6d0da78}"/>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2,PerMonitor</dpiAwareness>
      <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
    </windowsSettings>
  </application>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0" processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/>
    </dependentAssembly>
  </dependency>
</assembly>
"@
    [IO.File]::WriteAllText((Join-Path $work "app.manifest"), $manifest, (New-Object Text.UTF8Encoding($false)))
    # (no company name on purpose: the project is a hobby mod, not a company)
    $rc = @"
#pragma code_page(65001)
LANGUAGE 0, 0
1 ICON "app.ico"
1 24 "app.manifest"
1 RCDATA "payload.zip"
2 RCDATA "config.txt"
LANGUAGE 9, 1
1 VERSIONINFO
FILEVERSION $v4
PRODUCTVERSION $v4
FILEFLAGSMASK 0x3fL
FILEFLAGS 0x0L
FILEOS 0x40004L
FILETYPE 0x1L
FILESUBTYPE 0x0L
BEGIN
    BLOCK "StringFileInfo"
    BEGIN
        BLOCK "040904b0"
        BEGIN
            VALUE "FileDescription", "$Description"
            VALUE "FileVersion", "$Version"
            VALUE "InternalName", "$TempPrefix"
            VALUE "LegalCopyright", "Open source (MIT License). Unsigned."
            VALUE "OriginalFilename", "$([IO.Path]::GetFileName($Out))"
            VALUE "ProductName", "$Product"
            VALUE "ProductVersion", "$Version"
        END
    END
    BLOCK "VarFileInfo"
    BEGIN
        VALUE "Translation", 0x409, 1200
    END
END
"@
    [IO.File]::WriteAllText((Join-Path $work "stub.rc"), $rc, (New-Object Text.UTF8Encoding($false)))
    $exe = Join-Path $work "setup.exe"
    Push-Location $work
    try {
        # 32-bit on purpose: runs on 32-bit Windows too, and finds the 64-bit PowerShell through Sysnative when it must.
        $ErrorActionPreference = "Continue"   # (zig writes warnings to stderr)
        & $Zig cc -target x86-windows-gnu -Os -s -o $exe @CFlags stub.c stub.rc -lkernel32 -luser32 -lbcrypt -lshell32 "-Wl,--subsystem,windows" "-Wl,--dynamicbase" "-Wl,--nxcompat" 2>&1 | ForEach-Object { "$_" }
        $zigExit = $LASTEXITCODE
        $ErrorActionPreference = "Stop"
        if ($zigExit -ne 0 -or -not (Test-Path -LiteralPath $exe)) { throw "zig cc failed" }
    } finally { Pop-Location }

    if (-not $NoSelfTest) {
        $x = Join-Path $work "extracted"
        $p = Start-Process -FilePath $exe -ArgumentList @("--extract", "`"$x`"") -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "self-test: --extract exited $($p.ExitCode)" }
        $zz = [IO.Compression.ZipFile]::OpenRead($Zip)
        try {
            $n = 0
            foreach ($e in $zz.Entries) {
                if ($e.FullName.EndsWith("/") -or $e.FullName.EndsWith("\")) { continue }
                $f = Join-Path $x ($e.FullName -replace '/', '\')
                if (-not (Test-Path -LiteralPath $f)) { throw "self-test: $($e.FullName) was not extracted" }
                if ((Get-Item -LiteralPath $f).Length -ne $e.Length) { throw "self-test: size of $($e.FullName)" }
                $ms = New-Object IO.MemoryStream; $es = $e.Open(); $es.CopyTo($ms); $es.Close()
                $a = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($ms.ToArray())) -replace "-", "").ToLower()
                if ($a -ne (Sha256 $f)) { throw "self-test: content of $($e.FullName)" }
                $n++
            }
            $have = @(Get-ChildItem -LiteralPath $x -Recurse -File).Count
            if ($have -ne $n) { throw "self-test: $have files extracted, the zip has $n" }
        } finally { $zz.Dispose() }
        "self-test: $n files unpacked by the stub equal the zip"
    }
    New-Item -ItemType Directory -Force (Split-Path -Parent ([IO.Path]::GetFullPath($Out))) | Out-Null
    Copy-Item -LiteralPath $exe $Out -Force
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
"built $Out ($([int]((Get-Item -LiteralPath $Out).Length / 1KB)) KB, SHA-256 $(Sha256 $Out), payload SHA-256 $zipSha)"

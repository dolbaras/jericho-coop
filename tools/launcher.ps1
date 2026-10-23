# Jericho Co-op launcher (shipped as <game>\coop\coop-launcher.ps1; the installer's desktop shortcut
# runs it). Before the game starts it asks GitHub for the latest release of the mod; when that is
# newer than the installed one, it downloads the release's archive (checked against the SHA-256
# GitHub gives for it), runs that version's installer for this game folder (its window shows the
# steps and closes by itself) and then starts the game. Offline, on any error, or when the check
# takes too long, the game simply starts as it is.
# Usage: coop-launcher.ps1 [-NoUpdate] [-NoStart] [-Feed <url of a releases/latest JSON>]
param([switch] $NoUpdate, [switch] $NoStart, [string] $Feed = "")
$ErrorActionPreference = "Stop"
$coop = $PSScriptRoot
$game = Split-Path $coop -Parent
$feedUrl = if ($Feed) { $Feed } elseif ($env:JERICHO_COOP_FEED) { $env:JERICHO_COOP_FEED } else {
    "https://api.github.com/repos/dolbaras/jericho-coop/releases/latest" }
$log = Join-Path $coop "launcher-log.txt"
# Started from PowerShell 7, Windows PowerShell inherits its module path and some of its own
# commands fail to load: the installer started from here gets Windows PowerShell's own.
$env:PSModulePath = (@($env:PSModulePath -split ';') | Where-Object { $_ -and $_ -notmatch '\\PowerShell\\' }) -join ';'
function Log($s) { try { Add-Content -LiteralPath $log -Encoding UTF8 -Value ("{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $s) } catch { } }

$lang = (Get-UICulture).TwoLetterISOLanguageName
$T = @{
    en = @{ title = "Jericho Co-op"; found = "Co-op {0} is out (you have {1}). Downloading..."; verify = "Checking the download..."; failed = "The update could not be installed: {0}`nThe game starts with co-op {1}."; bad = "The download does not match the release's checksum." }
    ru = @{ title = "Jericho Co-op"; found = "Вышел кооп {0} (у вас {1}). Загрузка..."; verify = "Проверка загрузки..."; failed = "Обновление не удалось установить: {0}`nИгра запустится с коопом {1}."; bad = "Загрузка не совпадает с контрольной суммой выпуска." }
    de = @{ title = "Jericho Co-op"; found = "Koop {0} ist erschienen (du hast {1}). Download läuft..."; verify = "Download wird geprüft..."; failed = "Das Update konnte nicht installiert werden: {0}`nDas Spiel startet mit Koop {1}."; bad = "Der Download passt nicht zur Prüfsumme der Veröffentlichung." }
    fr = @{ title = "Jericho Co-op"; found = "Le coop {0} est sorti (vous avez {1}). Téléchargement..."; verify = "Vérification du téléchargement..."; failed = "La mise à jour n'a pas pu être installée : {0}`nLe jeu démarre avec le coop {1}."; bad = "Le téléchargement ne correspond pas à la somme de contrôle de la version." }
    es = @{ title = "Jericho Co-op"; found = "Ya está el cooperativo {0} (tienes {1}). Descargando..."; verify = "Comprobando la descarga..."; failed = "No se pudo instalar la actualización: {0}`nEl juego se inicia con el cooperativo {1}."; bad = "La descarga no coincide con la suma de comprobación de la versión." }
    it = @{ title = "Jericho Co-op"; found = "È uscito il co-op {0} (hai {1}). Download in corso..."; verify = "Verifica del download..."; failed = "Impossibile installare l'aggiornamento: {0}`nIl gioco parte con il co-op {1}."; bad = "Il download non corrisponde al checksum della versione." }
}
if (-not $T.ContainsKey($lang)) { $lang = "en" }
function L($k) { $T[$lang][$k] }

# Steam's copy: its app id from the library's appmanifest_<id>.acf whose installdir is this folder.
function Steam-AppId {
    if ($game -notmatch '^(.*\\steamapps)\\common\\([^\\]+)$') { return $null }
    $apps, $dir = $Matches[1], $Matches[2]
    foreach ($acf in Get-ChildItem -LiteralPath $apps -Filter "appmanifest_*.acf" -ErrorAction SilentlyContinue) {
        $text = Get-Content -LiteralPath $acf.FullName -Raw -ErrorAction SilentlyContinue
        if ($text -match ('"installdir"\s+"' + [regex]::Escape($dir) + '"') -and $text -match '"appid"\s+"(\d+)"') { return $Matches[1] }
    }
    $null
}

function Start-Game {
    # Steam's copy through Steam (its overlay, its own start); any other one by its exe (with
    # SMOD, bin\Jericho.exe is SMOD's starter, which runs the game itself).
    $app = Steam-AppId
    $how = if ($app) { "steam://rungameid/$app" } else { "bin\Jericho.exe" }
    Log ("start: $how" + $(if ($NoStart) { " (-NoStart)" } else { "" }))
    if ($NoStart) { return }
    if ($app) { Start-Process "steam://rungameid/$app" }
    else { Start-Process -FilePath (Join-Path $game "bin\Jericho.exe") -WorkingDirectory $game }
}

function Version-Of($s) {
    $s = ("$s".Trim()) -replace '^[vV]', ''
    try { return [version]$s } catch { return $null }
}

# A small window: one line and a bar.
$form = $null
function Show-Window($text) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $script:form = New-Object Windows.Forms.Form
    $form.Text = L "title"; $form.FormBorderStyle = "FixedSingle"; $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.StartPosition = "CenterScreen"; $form.ClientSize = New-Object Drawing.Size(460, 96)
    $form.BackColor = [Drawing.Color]::FromArgb(24, 24, 28); $form.ForeColor = [Drawing.Color]::FromArgb(232, 232, 236)
    $form.Font = New-Object Drawing.Font("Segoe UI", 10)
    $script:lbl = New-Object Windows.Forms.Label
    $lbl.Location = New-Object Drawing.Point(18, 16); $lbl.Size = New-Object Drawing.Size(424, 40); $lbl.Text = $text
    $form.Controls.Add($lbl)
    $bar = New-Object Windows.Forms.Panel
    $bar.Location = New-Object Drawing.Point(18, 64); $bar.Size = New-Object Drawing.Size(424, 10)
    $bar.BackColor = [Drawing.Color]::FromArgb(34, 34, 40)
    $script:fill = New-Object Windows.Forms.Panel
    $fill.Size = New-Object Drawing.Size(0, 10); $fill.BackColor = [Drawing.Color]::FromArgb(196, 40, 48)
    $bar.Controls.Add($fill); $form.Controls.Add($bar)
    try { $form.Icon = New-Object Drawing.Icon((Join-Path $coop "coop.ico"), 32, 32) } catch { }
    # a dark title bar like the installer's (Windows 10 2004+ / 11)
    $form.Add_HandleCreated({
        try {
            Add-Type -Namespace CoopLauncher -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);'
            $on = 1; [CoopLauncher.Dwm]::DwmSetWindowAttribute($this.Handle, 20, [ref]$on, 4) | Out-Null
        } catch { }
    })
    $form.Show()
    $form.Refresh()
    [Windows.Forms.Application]::DoEvents()
}
function Set-Progress($pct, $text) {
    if (-not $form) { return }
    if ($text) { $lbl.Text = $text }
    $fill.Width = [int](424 * [Math]::Max(0, [Math]::Min(100, $pct)) / 100)
    [Windows.Forms.Application]::DoEvents()
}

function Try-Update {
    $cur = Version-Of (Get-Content -LiteralPath (Join-Path $coop "version.txt") -TotalCount 1 -ErrorAction SilentlyContinue)
    if (-not $cur) { Log "no installed version"; return }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $req = [Net.HttpWebRequest]::Create($feedUrl)
    $req.UserAgent = "jericho-coop-launcher/$cur"; $req.Accept = "application/vnd.github+json"; $req.Timeout = 6000; $req.ReadWriteTimeout = 6000
    $resp = $req.GetResponse()
    $json = (New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd()
    $resp.Close()
    $rel = $json | ConvertFrom-Json
    $new = Version-Of $rel.tag_name
    Log "installed $cur, latest $($rel.tag_name)"
    if (-not $new -or $new -le $cur) { return }
    $asset = @($rel.assets | Where-Object { $_.name -like "jericho-coop-*.zip" })[0]
    if (-not $asset) { Log "no archive in the release"; return }
    # (only the mod's own release archive; another feed is for tests)
    if (-not $Feed -and -not $env:JERICHO_COOP_FEED -and "$($asset.browser_download_url)" -notlike "https://github.com/dolbaras/jericho-coop/releases/download/*") {
        Log "unexpected download url $($asset.browser_download_url)"; return
    }
    Show-Window ((L "found") -f $new, $cur)
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("jericho-coop-update-" + $new)
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp $asset.name
    # The download, chunk by chunk (the bar shows it).
    $dreq = [Net.HttpWebRequest]::Create($asset.browser_download_url)
    $dreq.UserAgent = "jericho-coop-launcher/$cur"; $dreq.Timeout = 30000; $dreq.ReadWriteTimeout = 30000
    $dresp = $dreq.GetResponse()
    $total = [double]$dresp.ContentLength
    $in = $dresp.GetResponseStream()
    $out = [IO.File]::Create($zip)
    try {
        $buf = New-Object byte[] 65536; $got = 0.0
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $n); $got += $n
            if ($total -gt 0) { Set-Progress (100 * $got / $total) $null }
        }
    } finally { $out.Close(); $in.Close(); $dresp.Close() }
    Set-Progress 100 (L "verify")
    # GitHub gives each asset's SHA-256 ("digest": "sha256:...").
    if ($asset.digest -and "$($asset.digest)" -like "sha256:*") {
        $want = ("$($asset.digest)".Substring(7)).ToUpper()
        # (.NET, not Get-FileHash: a script cmdlet that fails to load when this runs under PowerShell 7's module path)
        $fs = [IO.File]::OpenRead($zip)
        try { $have = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($fs)) -replace "-", "" } finally { $fs.Close() }
        if ($have -ne $want) { throw (L "bad") }
        Log "checksum ok $have"
    } else { Log "the release gives no checksum" }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, (Join-Path $tmp "x"))
    $inst = Join-Path $tmp "x\coop-installer.ps1"
    if (-not (Test-Path -LiteralPath $inst)) { throw "coop-installer.ps1 missing in $($asset.name)" }
    $form.Hide()
    # That version's installer, its window, for this folder; it closes by itself when done.
    $p = Start-Process powershell -PassThru -Wait -WindowStyle Hidden -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$inst`"", "-Game", "`"$game`"", "-AutoClose", "-NoShortcut")
    Log "installer exit $($p.ExitCode)"
    if ($p.ExitCode -ne 0) { throw "installer exit $($p.ExitCode)" }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# This folder's game already running (another copy elsewhere does not count): nothing to do.
if (Get-Process -Name Jericho, anselintegrationtestapp -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Path -or $_.Path.StartsWith($game + "\", [StringComparison]::OrdinalIgnoreCase) }) { Log "the game runs already"; exit 0 }
if (-not $NoUpdate) {
    try { Try-Update } catch {
        $why = $_.Exception.Message
        Log "update: $why"
        # (offline or GitHub slow: no message, the game just starts; a failed install is said)
        if ($form) {
            $form.Hide()
            $cur = Get-Content -LiteralPath (Join-Path $coop "version.txt") -TotalCount 1 -ErrorAction SilentlyContinue
            [Windows.Forms.MessageBox]::Show(((L "failed") -f $why, $cur), (L "title"), "OK", "Warning") | Out-Null
        }
    }
    if ($form) { $form.Close() }
}
Start-Game

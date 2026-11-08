# Offline check of the installer's and the launcher's texts in the mod's six languages (owner's rule: every text
# the mod adds or changes is in the player's language; the windows take Windows' language, the installer has a
# list too). For tools\installer.ps1 ($script:TEXTS) and tools\launcher.ps1 ($T): each of en ru de fr es it has
# exactly the English keys, no empty text, no text equal to the English one unless $SAME lists it, the same
# {0} {1} ... placeholders; every L "<key>" the script asks for exists; nothing shown is English text of its own
# ("ERROR: " in the installer's log, the launcher's thrown reasons). The tables are read from the scripts'
# syntax trees (SafeGetValue: constants only, nothing of the scripts runs).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_texts.ps1   (exit code 0 = all passed)
param([string] $Root = "")
$ErrorActionPreference = "Stop"
if (-not $Root) { $Root = Split-Path $PSScriptRoot -Parent }
$LANGS = @("en", "ru", "de", "fr", "es", "it")
# Texts that are the English ones in these languages, on purpose: "<script>:<key>" -> languages.
$SAME = @{
    "launcher:title" = "ru de fr es it"                  # Jericho Co-op+
    "installer:large_address_aware" = "fr es it"         # the exe flag's name
    "installer:error" = "es"                             # "Error: "
}
$script:pass = 0; $script:fail = 0
function Check($ok, $what) {
    if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL $what" }
}

function Read-Script($path) {
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    Check ($errs.Count -eq 0) "$path parses ($($errs.Count) errors)"
    $ast
}
function Text-Table($ast, $varText) {
    $asg = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left.Extent.Text -eq $varText }, $true))
    if ($asg.Count -ne 1) { return $null }
    $asg[0].Right.Expression.SafeGetValue()
}
function Placeholders($s) { (@([regex]::Matches($s, '\{\d+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique)) -join " " }

function Check-Table($name, $table) {
    if ($null -eq $table) { Check $false "${name}: text table found"; return }
    Check ((@($table.Keys | Sort-Object) -join " ") -eq (@($LANGS | Sort-Object) -join " ")) "${name}: languages $(@($table.Keys) -join ',')"
    $en = $table["en"]
    $used = @{}
    foreach ($lang in $LANGS) {
        $t = $table[$lang]
        if ($null -eq $t) { Check $false "${name} [$lang]: a table"; continue }
        foreach ($k in $en.Keys) {
            $v = $t[$k]
            if ([string]$v -eq "") { Check $false "${name}:$k [$lang]: missing"; continue }
            Check ((Placeholders $v) -eq (Placeholders $en[$k])) "${name}:$k [$lang]: placeholders '$(Placeholders $v)', English '$(Placeholders $en[$k])'"
            if ($lang -ne "en" -and $v -ceq $en[$k]) {
                $allowed = $SAME.ContainsKey("${name}:$k") -and (" " + $SAME["${name}:$k"] + " ").Contains(" $lang ")
                if ($allowed) { $used["${name}:$k $lang"] = $true }
                Check $allowed "${name}:$k [$lang]: the English text '$($en[$k])'"
            }
        }
        foreach ($k in $t.Keys) { Check $en.ContainsKey($k) "${name}:$k [$lang]: not in the English table" }
    }
    foreach ($id in @($SAME.Keys | Where-Object { $_.StartsWith("${name}:") })) {
        foreach ($lang in ($SAME[$id] -split " ")) { Check $used["$id $lang"] "SAME $id [$lang]: no longer the English text, take it off the list" }
    }
}
# Every L "<key>" call: the key in the English table; none built at run time.
function Check-Calls($name, $ast, $en) {
    $calls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq "L" }, $true))
    Check ($calls.Count -gt 0) "${name}: L calls found"
    foreach ($c in $calls) {
        $a = $c.CommandElements[1]
        if ($a -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            Check $en.ContainsKey($a.Value) "${name} line $($c.Extent.StartLineNumber): L `"$($a.Value)`" not in the English table"
        } else {
            Check $false "${name} line $($c.Extent.StartLineNumber): a key made at run time: $($c.Extent.Text)"
        }
    }
    $calls.Count
}

# --- the installer
$instPath = Join-Path $Root "tools\installer.ps1"
$inst = Read-Script $instPath
$instTexts = Text-Table $inst '$script:TEXTS'
Check-Table "installer" $instTexts
$nInst = if ($instTexts) { Check-Calls "installer" $inst $instTexts["en"] } else { 0 }
$instSrc = [IO.File]::ReadAllText($instPath)
# (the log box and the error box show the translated "error" text: "ERROR: " was English in every language)
Check (-not $instSrc.Contains('"ERROR: "')) "installer: an English 'ERROR: ' in the window's log"
Check ($instSrc -match '\$said = try \{ \(L "error"\)') "installer: the error box outside the steps says 'error' in the window's language"

# --- the launcher
$launPath = Join-Path $Root "tools\launcher.ps1"
$laun = Read-Script $launPath
$launTexts = Text-Table $laun '$T'
Check-Table "launcher" $launTexts
$nLaun = if ($launTexts) { Check-Calls "launcher" $laun $launTexts["en"] } else { 0 }
# A reason the launcher throws ends up in its "the update could not be installed: {0}" box: through L only.
$throws = @($laun.FindAll({ param($n) $n -is [System.Management.Automation.Language.ThrowStatementAst] }, $true))
foreach ($t in $throws) {
    Check ($null -ne $t.Pipeline -and $t.Pipeline.Extent.Text -match '^\(\(?L "') "launcher line $($t.Extent.StartLineNumber): a reason not through L: $($t.Extent.Text)"
}

$n = $script:pass + $script:fail
if ($script:fail -gt 0) { Write-Host "test_texts: $($script:fail) of $n checks FAILED"; exit 1 }
Write-Host "test_texts: $n/$n passed (installer: $($instTexts['en'].Count) texts, $nInst L calls; launcher: $($launTexts['en'].Count) texts, $nLaun L calls; 6 languages)"
exit 0

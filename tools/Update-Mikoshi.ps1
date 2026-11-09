# Update-Mikoshi.ps1
#
# Checks GitHub for a newer Mikoshi and installs it over your existing copy,
# keeping your settings.
#
# WHY THIS IS NOT A BUTTON IN THE MOD
# -----------------------------------
# Cyber Engine Tweaks runs mods in a sandboxed Lua VM with no network stack.
# There is no HTTP client, no sockets, and io is limited to the mod's own
# folder. A mod cannot fetch a URL, so it cannot find out that an update
# exists, let alone download one. That is a CET design decision and not
# something a mod can work around. So the check lives out here, where a
# process is allowed to talk to the internet.
#
# WHAT IT TOUCHES
# ---------------
# Only  <game>\bin\x64\plugins\cyber_engine_tweaks\mods\fixer.
# Your settings in that folder -- theme.txt, watch.txt, blocked.txt, folds.txt
# -- are carried across, and the whole folder is backed up first.

[CmdletBinding()]
param(
    # Where Cyberpunk 2077 is installed. Found automatically if omitted.
    [string] $GamePath,
    # Check and report, change nothing.
    [switch] $CheckOnly,
    # Install even when the installed version already matches.
    [switch] $Force,
    # Skip the confirmation prompt. For scripted use and for testing this
    # script itself, which cannot answer a prompt.
    [switch] $Yes
)

$ErrorActionPreference = 'Stop'
$Repo     = 'TmasLove/Mikoshi'
$ModDir   = 'bin\x64\plugins\cyber_engine_tweaks\mods\fixer'
$Keep     = @('theme.txt', 'watch.txt', 'blocked.txt', 'folds.txt')
$Headers  = @{ 'User-Agent' = 'Mikoshi-Updater' }

function Say   ($m) { Write-Host $m }
function Step  ($m) { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Warn  ($m) { Write-Host $m -ForegroundColor Yellow }
function Fail  ($m) { Write-Host $m -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- find game
function Find-GamePath {
    if ($GamePath) { return $GamePath }

    # A path remembered from last time sits next to this script.
    $memo = Join-Path $PSScriptRoot 'game-path.txt'
    if (Test-Path $memo) {
        $p = (Get-Content $memo -Raw).Trim()
        if ($p -and (Test-Path (Join-Path $p $ModDir))) { return $p }
    }

    # Steam: read the library list and look in each one.
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $cand = Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common\Cyberpunk 2077'
                if (Test-Path (Join-Path $cand $ModDir)) { return $cand }
            }
        }
    }

    # GOG and Epic both leave an uninstall entry with the install location.
    foreach ($root in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($k in Get-ItemProperty $root -ErrorAction SilentlyContinue) {
            if ($k.DisplayName -like '*Cyberpunk 2077*' -and $k.InstallLocation) {
                if (Test-Path (Join-Path $k.InstallLocation $ModDir)) { return $k.InstallLocation }
            }
        }
    }
    return $null
}

# ------------------------------------------------------------- versions
function Get-InstalledVersion ($modPath) {
    $init = Join-Path $modPath 'init.lua'
    if (-not (Test-Path $init)) { return $null }
    $m = [regex]::Match((Get-Content $init -Raw), "local\s+VERSION\s*=\s*'([^']+)'")
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# Compare "1.10" against "1.9" as numbers, not as text, so 1.10 is newer.
function Compare-Version ($a, $b) {
    $pa = @(($a -replace '^v', '') -split '[.\-]' | ForEach-Object { [int]($_ -replace '\D', '0') })
    $pb = @(($b -replace '^v', '') -split '[.\-]' | ForEach-Object { [int]($_ -replace '\D', '0') })
    for ($i = 0; $i -lt [Math]::Max($pa.Count, $pb.Count); $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $y = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($x -ne $y) { return $x - $y }
    }
    return 0
}

function Get-LatestTag {
    # Releases first, since a release is a deliberate publish. Tags are the
    # fallback, because pushing a tag is how this project publishes.
    try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers $Headers
        if ($rel.tag_name) { return @{ tag = $rel.tag_name; notes = $rel.body; kind = 'release' } }
    } catch { }
    try {
        $tags = Invoke-RestMethod "https://api.github.com/repos/$Repo/tags" -Headers $Headers
        $best = $null
        foreach ($t in $tags) {
            if ($t.name -notmatch '^v?\d') { continue }
            if (-not $best -or (Compare-Version $t.name $best) -gt 0) { $best = $t.name }
        }
        if ($best) { return @{ tag = $best; notes = $null; kind = 'tag' } }
    } catch {
        Fail "Could not reach GitHub: $($_.Exception.Message)"
    }
    return $null
}

# =========================================================================
Say ''
Say '  M I K O S H I   u p d a t e r'
Say '  --------------------------------'

$game = Find-GamePath
if (-not $game) {
    Warn 'Could not find a Cyberpunk 2077 install with Mikoshi in it.'
    Say  'Run this with the path, for example:'
    Say  '   .\Update-Mikoshi.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Cyberpunk 2077"'
    exit 1
}
$modPath = Join-Path $game $ModDir
Say "  game      $game"

$installed = Get-InstalledVersion $modPath
Say "  installed $(if ($installed) { $installed } else { 'unknown' })"

Step 'Checking GitHub'
$latest = Get-LatestTag
if (-not $latest) {
    Warn 'No releases or version tags published yet, so there is nothing to update to.'
    exit 0
}
Say "  latest    $($latest.tag)  (from the $($latest.kind) list)"

$newer = $true
if ($installed) { $newer = (Compare-Version $latest.tag $installed) -gt 0 }

if (-not $newer -and -not $Force) {
    Say ''
    Say '  You are up to date.'
    exit 0
}
if ($newer) { Say ''; Say "  An update is available: $installed -> $($latest.tag)" -ForegroundColor Green }
else        { Say ''; Warn "  Not newer, but -Force was given." }

if ($latest.notes) { Say ''; Say '  Release notes:'; Say ($latest.notes.Trim()) }

if ($CheckOnly) { Say ''; Say '  -CheckOnly, so nothing was changed.'; exit 0 }

Say ''
Warn '  Close Cyberpunk 2077 before continuing. Files in use cannot be replaced.'
if ($Yes) {
    Say '  -Yes was given, so installing without asking.'
} else {
    $ans = Read-Host '  Install it now? (y/N)'
    if ($ans -notmatch '^[Yy]') { Say '  Cancelled. Nothing was changed.'; exit 0 }
}

# ------------------------------------------------------------- download
Step 'Downloading'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mikoshi-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$zip = Join-Path $tmp 'src.zip'
$url = "https://github.com/$Repo/archive/refs/tags/$($latest.tag).zip"
Say "  $url"
Invoke-WebRequest -Uri $url -OutFile $zip -Headers $Headers
Expand-Archive -Path $zip -DestinationPath $tmp -Force

$src = Get-ChildItem -Path $tmp -Recurse -Directory -Filter 'fixer' |
       Where-Object { Test-Path (Join-Path $_.FullName 'init.lua') } |
       Select-Object -First 1
if (-not $src) { Fail '  That archive has no fixer folder with an init.lua in it. Nothing was changed.' }

# ------------------------------------------------------------- back up
Step 'Backing up your current copy'
$backup = Join-Path $game ("bin\x64\plugins\cyber_engine_tweaks\mods\fixer.backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (Test-Path $modPath) {
    Copy-Item $modPath $backup -Recurse -Force
    Say "  $backup"
}

# ------------------------------------------- keep settings, replace the rest
Step 'Installing'
$saved = @{}
foreach ($f in $Keep) {
    $p = Join-Path $modPath $f
    if (Test-Path $p) { $saved[$f] = Get-Content $p -Raw }
}

Get-ChildItem $modPath -File -ErrorAction SilentlyContinue |
    Where-Object { $Keep -notcontains $_.Name } |
    Remove-Item -Force

Copy-Item (Join-Path $src.FullName '*') $modPath -Recurse -Force

foreach ($f in $saved.Keys) {
    Set-Content -Path (Join-Path $modPath $f) -Value $saved[$f] -NoNewline
    Say "  kept $f"
}

# The readme ships in the download but is not part of the repo fixer folder,
# so a straight copy of that folder leaves it deleted. Put it back from the
# archive, where it lives one level up.
$readme = Get-ChildItem -Path $tmp -Recurse -File -Filter "READ THIS FIRST.txt" | Select-Object -First 1
if ($readme) {
    Copy-Item $readme.FullName (Join-Path $modPath $readme.Name) -Force
    Say "  restored $($readme.Name)"
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

$now = Get-InstalledVersion $modPath
Say ''
if ($now -and (Compare-Version $now $installed) -gt 0) {
    Say "  Done. $installed -> $now" -ForegroundColor Green
} else {
    Warn "  Files were copied, but init.lua still reports '$now'."
    Warn "  Your previous copy is at $backup if you want it back."
}
Say '  Start the game, open the CET overlay and press Reload All Mods.'
Say ''

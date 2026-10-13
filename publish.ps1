#Requires -Version 7.0
<#
.SYNOPSIS
    Builds the Android plugin AARs, runs the Kotlin and GDScript tests, and writes the release folder:
    dist/<version>/ with the addon zip and a manifest.json (name, version, archive sha256 and a sha256 for every addon file)
    in the schema the consuming games' vendoring tests read.
.PARAMETER Version
    Release version. Defaults to the version in addons/syntaxcircus_games/plugin.cfg.
.PARAMETER GodotPath
    Godot 4.7.2 editor executable for the GDScript tests. Defaults to $env:GODOT_PATH.
.PARAMETER SkipTests
    Skip the Kotlin and GDScript tests (the build still runs).
.PARAMETER DryRun
    Build, test and write dist/ but do nothing else. Present for parity with the other Syntax Circus repos: this repo publishes
    by tagging and attaching dist/<version>/ to the release, which is a manual step.
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$GodotPath = $env:GODOT_PATH,
    [string]$JavaHome = $env:JAVA_HOME,
    [string]$AndroidHome = $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }),
    [switch]$SkipTests,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$addon = Join-Path $root 'addons/syntaxcircus_games'
$android = Join-Path $root 'android'

if (-not $Version) {
    $cfg = Get-Content -LiteralPath (Join-Path $addon 'plugin.cfg') -Raw
    if ($cfg -notmatch '(?m)^version="([^"]+)"') { throw 'plugin.cfg has no version' }
    $Version = $Matches[1]
}
Write-Host "==> SyntaxCircus.Godot.GamesServices $Version" -ForegroundColor Cyan

if (-not $JavaHome) { throw 'Set JAVA_HOME (JDK 17) or pass -JavaHome' }
if (-not $AndroidHome) { throw 'Set ANDROID_HOME or pass -AndroidHome' }
$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidHome
$sdkDir = $AndroidHome.Replace('\', '/')
Set-Content -LiteralPath (Join-Path $android 'local.properties') -Value "sdk.dir=$sdkDir" -Encoding ascii

Write-Host '==> Gradle build' -ForegroundColor Cyan
$tasks = @(':plugin:assembleDebug', ':plugin:assembleRelease')
if (-not $SkipTests) { $tasks = @(':plugin:testDebugUnitTest') + $tasks }
Push-Location $android
try {
    & (Join-Path $android 'gradlew.bat') --no-daemon @tasks
    if ($LASTEXITCODE -ne 0) { throw 'Gradle build failed' }
} finally { Pop-Location }

foreach ($flavor in 'debug', 'release') {
    $source = Join-Path $android "plugin/build/outputs/aar/plugin-$flavor.aar"
    $target = Join-Path $addon "bin/$flavor/SyntaxCircusGames-$flavor.aar"
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
}

if (-not $SkipTests) {
    if (-not $GodotPath) { throw 'Set GODOT_PATH or pass -GodotPath (or use -SkipTests)' }
    Write-Host '==> GDScript tests' -ForegroundColor Cyan
    foreach ($test in Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Filter 'test_*.gd') {
        $name = [IO.Path]::GetFileNameWithoutExtension($test.Name)
        & $GodotPath --headless --path $root --script "res://tests/$name.gd" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "GDScript test $name failed" }
    }
}

Write-Host '==> dist' -ForegroundColor Cyan
$dist = Join-Path $root "dist/$Version"
if (Test-Path -LiteralPath $dist) { Remove-Item -LiteralPath $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist | Out-Null

# Editor-written files never ship: .uid beside scripts and .import beside imported assets.
$files = Get-ChildItem -LiteralPath $addon -Recurse -File | Where-Object { $_.Extension -notin '.uid', '.import' } | Sort-Object FullName
$entries = foreach ($file in $files) {
    $relative = 'addons/syntaxcircus_games/' + $file.FullName.Substring($addon.Length + 1).Replace('\', '/')
    [ordered]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
}

$archiveName = "SyntaxCircus.Godot.GamesServices-$Version.zip"
$archive = Join-Path $dist $archiveName
$stage = Join-Path $dist 'stage'
New-Item -ItemType Directory -Path (Join-Path $stage 'addons') | Out-Null
Copy-Item -LiteralPath $addon -Destination (Join-Path $stage 'addons/syntaxcircus_games') -Recurse
Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object { $_.Extension -in '.uid', '.import' } | Remove-Item -Force
Compress-Archive -Path (Join-Path $stage 'addons') -DestinationPath $archive
Remove-Item -LiteralPath $stage -Recurse -Force

$manifest = [ordered]@{
    name           = 'SyntaxCircus.Godot.GamesServices'
    source         = 'https://github.com/Syntax-Circus/SyntaxCircus.Godot.GamesServices'
    version        = "v$Version"
    release        = "https://github.com/Syntax-Circus/SyntaxCircus.Godot.GamesServices/releases/tag/v$Version"
    archive        = $archiveName
    archive_sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    license        = 'MIT'
    godot          = '4.7'
    notes          = 'Copied byte for byte into a game under addons/syntaxcircus_games. The Android plugin singleton is SyntaxCircusGames; the iOS adapter drives the GameCenterKit singleton, which the game vendors separately. Exclude addons/syntaxcircus_games/** from the exported PCK.'
    files          = @($entries)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dist 'manifest.json') -Encoding utf8

Write-Host "==> Done: $dist ($($entries.Count) files)" -ForegroundColor Green
if ($DryRun) { Write-Host 'Dry run: nothing else to do. To release, commit, tag v$Version and attach dist/$Version/.' }

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
    Build, test and write dist/ locally. This script never publishes; the tag release workflow uploads its outputs.
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
if ($Version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'Version must be X.Y.Z (without a v prefix)' }
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
$sourceCommit = $null
# Source archives have no repository metadata; do not inherit an enclosing checkout.
if (Test-Path -LiteralPath (Join-Path $root '.git')) {
    $sourceCommit = & git -C $root rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot determine source commit' }
}
& (Join-Path $root 'scripts/package-release.ps1') -AddonPath $addon -Version $Version -OutputDirectory (Join-Path $root 'dist') -SourceCommit $sourceCommit
if ($DryRun) { Write-Host 'Dry run: package built and tested locally; no tag or GitHub release created.' }

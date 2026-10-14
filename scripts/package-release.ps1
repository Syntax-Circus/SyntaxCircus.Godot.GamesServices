#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AddonPath,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$SourceCommit
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'Version must be X.Y.Z (without a v prefix)' }
$addon = (Resolve-Path -LiteralPath $AddonPath).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
if (-not (Test-Path -LiteralPath $addon -PathType Container)) { throw 'AddonPath must be a directory' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
$separator = [IO.Path]::DirectorySeparatorChar
if ($output.Equals($addon, [StringComparison]::OrdinalIgnoreCase) -or $output.StartsWith($addon + $separator, [StringComparison]::OrdinalIgnoreCase)) { throw 'OutputDirectory must be outside the addon' }
$dist = Join-Path $output $Version
if (Test-Path -LiteralPath $dist) { throw "Release directory already exists: $dist" }
$cfg = Get-Content -LiteralPath (Join-Path $addon 'plugin.cfg') -Raw
if ($cfg -notmatch '(?m)^version="[^"]+"\s*$') { throw 'plugin.cfg has no version' }
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$stage = Join-Path $dist 'stage'
$stagedAddon = Join-Path $stage 'addons/syntaxcircus_games'
New-Item -ItemType Directory -Path $stagedAddon -Force | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $addon -Recurse -File | Where-Object { $_.Extension -notin '.uid', '.import' }) {
    $relative = [IO.Path]::GetRelativePath($addon, $file.FullName)
    $target = Join-Path $stagedAddon $relative
    New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target
}
$stamped = [regex]::Replace($cfg, '(?m)^version="[^"]+"[ \t]*', ('version="' + $Version + '"'))
[IO.File]::WriteAllText((Join-Path $stagedAddon 'plugin.cfg'), $stamped, [Text.UTF8Encoding]::new($false))
$entries = @(foreach ($file in Get-ChildItem -LiteralPath $stagedAddon -Recurse -File | Sort-Object FullName) {
    [ordered]@{
        path = 'addons/syntaxcircus_games/' + [IO.Path]::GetRelativePath($stagedAddon, $file.FullName).Replace('\', '/')
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})
$archiveName = "SyntaxCircus.Godot.GamesServices-$Version.zip"
$archive = Join-Path $dist $archiveName
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $archive)
$resolvedStage = (Resolve-Path -LiteralPath $stage).Path
if (-not $resolvedStage.StartsWith([IO.Path]::GetFullPath($dist) + $separator, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging cleanup path' }
Remove-Item -LiteralPath $resolvedStage -Recurse -Force
$manifest = [ordered]@{
    name = 'SyntaxCircus.Godot.GamesServices'
    source = 'https://github.com/Syntax-Circus/SyntaxCircus.Godot.GamesServices'
    version = "v$Version"
    release = "https://github.com/Syntax-Circus/SyntaxCircus.Godot.GamesServices/releases/tag/v$Version"
    archive = $archiveName
    archive_sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    license = 'MIT'
    godot = '4.7'
    notes = 'Copied byte for byte into a game under addons/syntaxcircus_games. The Android plugin singleton is SyntaxCircusGames; the iOS adapter drives the GameCenterKit singleton, which the game vendors separately. Exclude addons/syntaxcircus_games/** from the exported PCK.'
    files = $entries
}
if ($SourceCommit) { $manifest.source_commit = $SourceCommit }
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dist 'manifest.json') -Encoding utf8
Write-Host "==> Packaged: $dist ($($entries.Count) files)"

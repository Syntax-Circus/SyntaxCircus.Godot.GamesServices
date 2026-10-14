#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot '../scripts/package-release.ps1'
if (-not (Test-Path $helper)) { throw 'Release packager is missing' }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('games-release-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixture/addon/sub" -Force | Out-Null
Set-Content "$fixture/addon/plugin.cfg" ("[plugin]" + [Environment]::NewLine + 'version="0.1.0"') -NoNewline
Set-Content "$fixture/addon/sub/example.gd" 'extends RefCounted'
Set-Content "$fixture/addon/sub/example.gd.uid" 'do not ship'
Set-Content "$fixture/addon/sub/icon.png.import" 'do not ship'
$original = Get-Content "$fixture/addon/plugin.cfg" -Raw
& $helper -AddonPath "$fixture/addon" -Version '0.1.1' -OutputDirectory "$fixture/out" -SourceCommit ('a' * 40)
$release = "$fixture/out/0.1.1"
$manifest = Get-Content "$release/manifest.json" -Raw | ConvertFrom-Json
Expand-Archive "$release/$($manifest.archive)" "$fixture/extracted"
if ((Get-Content "$fixture/addon/plugin.cfg" -Raw) -cne $original) { throw 'Source addon was modified' }
if ((Get-Content "$fixture/extracted/addons/syntaxcircus_games/plugin.cfg" -Raw) -notmatch 'version="0.1.1"') { throw 'Archive version was not stamped' }
if ($manifest.version -ne 'v0.1.1' -or $manifest.source_commit -ne ('a' * 40)) { throw 'Manifest version/provenance mismatch' }
$actual = @(Get-ChildItem "$fixture/extracted" -File -Recurse)
if ($actual.Count -ne 2 -or $manifest.files.Count -ne 2) { throw 'Archive contains editor files or omits manifest entries' }
foreach ($entry in $manifest.files) {
    $hash = (Get-FileHash (Join-Path "$fixture/extracted" $entry.path) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $entry.sha256) { throw "Archived file hash mismatch: $($entry.path)" }
}
if ((Get-FileHash "$release/$($manifest.archive)" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.archive_sha256) { throw 'Archive hash mismatch' }
foreach ($version in '../escape', 'v0.1.1', '0.1', '01.1.1') {
    $rejected = $false
    try { & $helper -AddonPath "$fixture/addon" -Version $version -OutputDirectory "$fixture/invalid" } catch { $rejected = $true }
    if (-not $rejected) { throw "Accepted invalid version $version" }
}
$rejected = $false
try { & $helper -AddonPath "$fixture/addon" -Version '0.1.1' -OutputDirectory "$fixture/out" } catch { $rejected = $true }
if (-not $rejected) { throw 'Existing release was overwritten' }
$rejected = $false
try { & $helper -AddonPath "$fixture/addon" -Version '0.1.2' -OutputDirectory "$fixture/addon/out" } catch { $rejected = $true }
if (-not $rejected) { throw 'Accepted output inside source addon' }
Write-Host 'PASS: staged version, untouched source, exact archive hashes, exclusions, invalid versions, safe output'

# ============================================================
# Wild Papagayo - Hotel Legacy Publish (All) v1.0
# hotel-generator.ps1 reads from knowledge/hotels/*.json (legacy
# flat schema), but edits -- including experience_scores from
# hotel-experience-scorer.ps1 -- land on knowledge/master/hotels.
# Without this sync step, hotel pages silently render stale data.
# Runs the existing per-hotel Convert-MasterToLegacyHotel publish
# step across every hotel. No Claude calls, fast, safe to run
# every build.
# ============================================================
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$masterDir = Join-Path $root 'knowledge\master\hotels'

$hotelFiles = Get-ChildItem $masterDir -Filter '*.json' -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' }
foreach ($file in $hotelFiles) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'wild-intelligence-engine.ps1') -EntityId $file.BaseName -PublishLegacy | Out-Null
    Write-Host "Synced legacy profile: $($file.BaseName)"
}
Write-Host "Hotel legacy publish complete: $($hotelFiles.Count) hotel(s)."

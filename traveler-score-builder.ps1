# Traveler Score Builder -- Formula v2.1 (frozen)
# Single-purpose, auditable implementation of the frozen Traveler Scores
# Formula v2.1. Computes intelligence.traveler_scores.{families,seniors,
# adventure,wildlife,relaxation} from existing structured tour data only.
#
# Does NOT generate primary_category, difficulty, best_for, itinerary_rules,
# or any other intelligence field -- that remains tour-intelligence-builder.ps1's
# job (untracked legacy script, untouched by this file).
#
# Usage:
#   .\traveler-score-builder.ps1 -TourIds congotrail                 (dry-run)
#   .\traveler-score-builder.ps1 -TourIds congotrail,laleona -Write  (write)
#
# Dry-run (no -Write) is the only default behavior. There is no "-All" /
# wildcard shortcut -- every invocation must explicitly name its tour IDs.

param(
    [Parameter(Mandatory = $true)]
    [string[]]$TourIds,

    [switch]$Write,

    [switch]$NoBackup
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$toursDir = Join-Path $root "knowledge\tours"
$backupRoot = Join-Path $root "knowledge\backups\traveler-scores"

if (-not (Test-Path $toursDir)) {
    throw "Tours directory not found: $toursDir"
}

# ---- Minimal generic helpers (no legacy profile-generation logic) ----

function Get-PropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function Get-ScoreBand {
    param([double]$Value)
    $clamped = [Math]::Max(0, [Math]::Min(100, $Value))
    $bands = @(0, 25, 50, 75, 100)
    $best = $bands[0]
    $bestDiff = [Math]::Abs($bands[0] - $clamped)
    foreach ($b in $bands) {
        $diff = [Math]::Abs($b - $clamped)
        if ($diff -lt $bestDiff) { $best = $b; $bestDiff = $diff }
    }
    return $best
}

function Get-AccordionRestrictionText {
    param($Tour)
    $pc = Get-PropertyValue $Tour "page_content" $null
    $accordion = Get-PropertyValue $pc "accordion" $null
    $gc = @((Get-PropertyValue $accordion "guest_considerations" @()))
    $bya = @((Get-PropertyValue $accordion "before_you_arrive" @()))
    $combined = @($gc) + @($bya)
    $text = ($combined -join " ") -replace '<[^>]+>', ''
    return $text
}

function Test-FamiliesRestrictionText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if ([regex]::IsMatch($Text, 'not suitable for (guests|children|anyone|those|people)', 'IgnoreCase')) { return $true }
    if ($Text.ToLowerInvariant().Contains('heart condition')) { return $true }
    return $false
}

function Test-SeniorsRestrictionText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $lower = $Text.ToLowerInvariant()
    foreach ($kw in @('knee', 'joint', 'heart condition', 'mobility', 'significant height', 'steep')) {
        if ($lower.Contains($kw)) { return $true }
    }
    return $false
}

# ---- Formula v2.1 (frozen spec) ----

$Script:HighAdventureActivities = @('atv', 'ziplining', 'rafting', 'tubing', 'horseback-riding', 'hiking', 'hanging-bridges')
$Script:WildlifeSpeciesActivities = @('sloth-watching', 'turtle-watching')
$Script:WildlifeGenericActivities = @('wildlife-watching')

function Get-TravelerScoresV21 {
    param($Tour)

    $flags = New-Object System.Collections.Generic.List[string]

    $activityIds = @((Get-PropertyValue $Tour "activity_ids" @()))
    $minimumAge = Get-PropertyValue $Tour "minimum_age" $null
    $difficulty = [string](Get-PropertyValue $Tour "difficulty" "")
    $itineraryBlock = Get-PropertyValue $Tour "itinerary" $null
    $intensity = [string](Get-PropertyValue $itineraryBlock "intensity" "")
    $intel = Get-PropertyValue $Tour "intelligence" $null
    $energyLevel = [string](Get-PropertyValue $intel "energy_level" "")
    $durationHours = Get-PropertyValue $intel "duration_hours" $null
    $primaryCategory = [string](Get-PropertyValue $intel "primary_category" "")

    if ($activityIds.Count -eq 0) { $flags.Add("empty activity_ids") | Out-Null }
    if ($null -eq $minimumAge) { $flags.Add("missing minimum_age") | Out-Null }
    if ([string]::IsNullOrWhiteSpace($difficulty)) { $flags.Add("missing difficulty") | Out-Null }
    if ([string]::IsNullOrWhiteSpace($intensity) -and [string]::IsNullOrWhiteSpace($energyLevel)) {
        $flags.Add("missing intensity AND energy_level") | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($intensity)) {
        $intensityKey = $intensity.ToLowerInvariant()
    } elseif ($energyLevel -eq "High") { $intensityKey = "heavy" }
    elseif ($energyLevel -eq "Low") { $intensityKey = "light" }
    elseif (-not [string]::IsNullOrWhiteSpace($energyLevel)) { $intensityKey = "moderate" }
    else { $intensityKey = "moderate" }

    # ---- ADVENTURE ----
    $nAdv = @($activityIds | Where-Object { $Script:HighAdventureActivities -contains $_ }).Count
    $advBase = switch ($nAdv) { 0 { 0 } 1 { 25 } 2 { 50 } default { 75 } }
    $advBonus = switch ($intensityKey) { "heavy" { 50 } "light" { 0 } default { 25 } }
    $adventureRaw = $advBase + $advBonus
    if ($nAdv -eq 0 -and $difficulty -eq "Easy") { $adventureRaw = 0 }
    $adventure = Get-ScoreBand $adventureRaw

    # ---- WILDLIFE ----
    $nSpecies = @($activityIds | Where-Object { $Script:WildlifeSpeciesActivities -contains $_ }).Count
    $nGeneric = @($activityIds | Where-Object { $Script:WildlifeGenericActivities -contains $_ }).Count
    $weighted = ($nSpecies * 2) + ($nGeneric * 1)
    $wildlife = switch ($weighted) { 0 { 0 } 1 { 50 } 2 { 75 } default { 100 } }
    if ($primaryCategory -eq "Nature & Wildlife" -and $weighted -eq 0) {
        $flags.Add("category=Nature & Wildlife but 0 wildlife activities") | Out-Null
    }
    if ($weighted -ge 2 -and $primaryCategory -ne "Nature & Wildlife") {
        $flags.Add("strong wildlife activities but category != Nature & Wildlife") | Out-Null
    }

    $restrictionText = Get-AccordionRestrictionText $Tour

    # ---- FAMILIES ----
    if ($null -eq $minimumAge) { $famBase = 50 }
    elseif ($minimumAge -eq 0) { $famBase = 100 }
    elseif ($minimumAge -ge 1 -and $minimumAge -le 5) { $famBase = 75 }
    elseif ($minimumAge -ge 6 -and $minimumAge -le 9) { $famBase = 50 }
    else { $famBase = 25 }
    $famPenalty = 0
    if ($intensityKey -eq "heavy") { $famPenalty += 25 }
    if ($null -ne $durationHours -and [double]$durationHours -gt 10) { $famPenalty += 25 }
    if (Test-FamiliesRestrictionText $restrictionText) { $famPenalty += 25 }
    $families = Get-ScoreBand ($famBase - $famPenalty)

    # ---- SENIORS ----
    switch ($difficulty) {
        "Easy" { $seniorBase = 100 }
        "Easy to Moderate" { $seniorBase = 75 }
        "Moderate" { $seniorBase = 50 }
        default { $seniorBase = $(if ([string]::IsNullOrWhiteSpace($difficulty)) { 50 } else { 25 }) }
    }
    $seniorPenalty = 0
    if ($null -ne $durationHours -and [double]$durationHours -gt 10) { $seniorPenalty += 25 }
    if (Test-SeniorsRestrictionText $restrictionText) { $seniorPenalty += 25 }
    if ($activityIds -contains "night-tour") { $seniorPenalty += 25 }
    $seniors = Get-ScoreBand ($seniorBase - $seniorPenalty)

    # ---- RELAXATION ----
    $relaxBase = switch ($intensityKey) { "light" { 75 } "heavy" { 25 } default { 50 } }
    $relaxBonus = 0
    if ($activityIds -contains "hot-springs") { $relaxBonus += 25 }
    if ($activityIds -contains "boat-tour") { $relaxBonus += 25 }
    $relaxPenalty = $(if ($null -ne $durationHours -and [double]$durationHours -gt 10) { 25 } else { 0 })
    $relaxation = Get-ScoreBand ($relaxBase + $relaxBonus - $relaxPenalty)

    return [pscustomobject]@{
        families = $families
        seniors = $seniors
        adventure = $adventure
        wildlife = $wildlife
        relaxation = $relaxation
        flags = @($flags)
    }
}

# ---- Runner ----

Write-Host ""
Write-Host "Traveler Score Builder -- Formula v2.1 -- $(if ($Write) { 'WRITE MODE' } else { 'DRY-RUN MODE (no files will be modified)' })" -ForegroundColor Cyan
Write-Host ""

foreach ($id in $TourIds) {
    $path = Join-Path $toursDir "$id.json"
    if (-not (Test-Path $path)) {
        Write-Host "SKIP $id -- tour file not found: $path" -ForegroundColor Red
        continue
    }

    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $tour = $raw | ConvertFrom-Json
    $result = Get-TravelerScoresV21 $tour

    $flagText = if ($result.flags.Count -gt 0) { " | FLAGS: " + ($result.flags -join "; ") } else { "" }
    Write-Host ("{0,-30} F:{1,-4} S:{2,-4} A:{3,-4} W:{4,-4} R:{5,-4}{6}" -f $tour.id, $result.families, $result.seniors, $result.adventure, $result.wildlife, $result.relaxation, $flagText)

    if (-not $Write) { continue }

    # ---- Write mode: surgical, byte-preserving replacement only ----

    $intel = Get-PropertyValue $tour "intelligence" $null
    if ($null -eq $intel) {
        Write-Host "  SKIP WRITE $($tour.id): no existing intelligence block (this script never creates one)" -ForegroundColor Red
        continue
    }
    $existingScores = Get-PropertyValue $intel "traveler_scores" $null
    if ($null -eq $existingScores) {
        Write-Host "  SKIP WRITE $($tour.id): no existing traveler_scores block" -ForegroundColor Red
        continue
    }

    $blockMatch = [regex]::Match($raw, '"traveler_scores":\s*\{(?<inner>.*?)\}', 'Singleline')
    if (-not $blockMatch.Success) {
        Write-Host "  SKIP WRITE $($tour.id): could not locate traveler_scores block in raw text" -ForegroundColor Red
        continue
    }

    $inner = $blockMatch.Groups['inner'].Value
    $fieldMap = [ordered]@{
        'families' = $result.families; 'seniors' = $result.seniors
        'adventure' = $result.adventure; 'wildlife' = $result.wildlife
        'relaxation' = $result.relaxation
    }

    # Verify every target key exists exactly once before changing anything --
    # abort this tour entirely if any target is missing or ambiguous.
    $abort = $false
    foreach ($fieldName in $fieldMap.Keys) {
        $matches = [regex]::Matches($inner, """$fieldName"":\s*\d+")
        if ($matches.Count -ne 1) {
            Write-Host "  SKIP WRITE $($tour.id): field '$fieldName' occurs $($matches.Count) time(s) in traveler_scores (expected exactly 1)" -ForegroundColor Red
            $abort = $true
        }
    }
    if ($abort) { continue }

    $newInner = $inner
    foreach ($fieldName in $fieldMap.Keys) {
        $newInner = $newInner -replace "(""$fieldName"":\s*)\d+", "`${1}$($fieldMap[$fieldName])"
    }

    $newBlock = '"traveler_scores":' + $blockMatch.Value.Substring('"traveler_scores":'.Length, $blockMatch.Value.IndexOf('{') - '"traveler_scores":'.Length) + '{' + $newInner + '}'
    $newRaw = $raw.Substring(0, $blockMatch.Index) + $newBlock + $raw.Substring($blockMatch.Index + $blockMatch.Length)

    if ($newRaw -eq $raw) {
        Write-Host "  NOTE $($tour.id): computed scores identical to existing values, no change written" -ForegroundColor DarkGray
        continue
    }

    if (-not $NoBackup) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupDir = Join-Path $backupRoot $stamp
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        Copy-Item $path (Join-Path $backupDir "$id.json")
    }

    [System.IO.File]::WriteAllText($path, $newRaw, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  WRITTEN $($tour.id)" -ForegroundColor Green
}

Write-Host ""

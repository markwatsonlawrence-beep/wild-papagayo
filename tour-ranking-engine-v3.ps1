# Tour Ranking Engine v3 -- B3 Curated+Fit (validated, approved)
# Single-purpose, auditable implementation of the approved V3-B3 formula.
# Extends V1-CLEAN (tour-ranking-engine-v2.ps1) with two changes only:
#   1. Hard eligibility gate (active status, confirmed pricing, supported
#      pickup zone) applied BEFORE scoring -- ineligible tours never appear
#      in the ranked output at all, rather than being scored and penalized.
#   2. A small +3 "hotel curated bonus" when the tour appears in the
#      hotel's own hand-curated hotel.recommendations.featured_tours list --
#      a signal V1-CLEAN never read. Deliberately small (see the V3-B
#      low-curation-bonus simulation): large enough to nudge borderline
#      rankings, never large enough to force a weak-fit tour into a top-3.
#
# Pickup zone match/no-zone is now eligibility-only (0 score contribution)
# rather than a +25/+6/-20 scoring term -- mismatches are excluded outright
# instead of being scored down, so pickup never appears in the point total.
#
# This script does NOT touch tour-ranking-engine.ps1 or
# tour-ranking-engine-v2.ps1, and does not modify hotel-generator.ps1 or
# any public HTML. It has no public consumer yet.
#
# Usage:
#   .\tour-ranking-engine-v3.ps1                              (dry-run, all hotels)
#   .\tour-ranking-engine-v3.ps1 -HotelIds four-seasons-papagayo   (dry-run, one hotel)
#   .\tour-ranking-engine-v3.ps1 -HotelIds four-seasons-papagayo -Write  (write, one hotel)
#
# Dry-run (no -Write) is the default and never writes anything. Write mode
# requires -HotelIds explicitly -- there is no "-Write all hotels" shortcut.
# Write mode outputs to knowledge\recommendations\rankings-v3\, a directory
# separate from both the legacy knowledge\recommendations\rankings\ and the
# V1-CLEAN knowledge\recommendations\rankings-v2\ artifacts.

param(
    [string[]]$HotelIds,
    [switch]$Write
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$hotelDir = Join-Path $root "knowledge\master\hotels"
$tourDir = Join-Path $root "knowledge\tours"
$outputDir = Join-Path $root "knowledge\recommendations\rankings-v3"

if ($Write -and (-not $HotelIds -or $HotelIds.Count -eq 0)) {
    throw "Write mode requires explicit -HotelIds. There is no write-all shortcut."
}

function Get-PropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "JSON file not found: $Path" }
    return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Normalize-Key {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return $Value.Trim().ToLowerInvariant()
}

function Get-HotelProfileV3 {
    param($Hotel, [string]$FallbackId)
    $identity = Get-PropertyValue $Hotel "identity" $null
    $location = Get-PropertyValue $Hotel "location" $null
    $scores = Get-PropertyValue $Hotel "experience_scores" $null
    $recommendations = Get-PropertyValue $Hotel "recommendations" $null
    $id = [string](Get-PropertyValue $identity "id" "")
    if ([string]::IsNullOrWhiteSpace($id)) { $id = $FallbackId }
    return [pscustomobject]@{
        id = $id
        pickup_zone = Normalize-Key ([string](Get-PropertyValue $location "tour_pickup_zone" ""))
        family_weight = [double](Get-PropertyValue (Get-PropertyValue $scores "families" $null) "score" 0)
        wellness_weight = [double](Get-PropertyValue (Get-PropertyValue $scores "wellness" $null) "score" 0)
        adventure_weight = [double](Get-PropertyValue (Get-PropertyValue $scores "adventure_access" $null) "score" 0)
        featured_tours = @((Get-PropertyValue $recommendations "featured_tours" @()))
    }
}

function Get-TourProfileV3 {
    param($Tour)
    $intel = Get-PropertyValue $Tour "intelligence" $null
    $travelerScores = Get-PropertyValue $intel "traveler_scores" $null
    $pricing = Get-PropertyValue $Tour "pricing" $null
    $pickupZones = @((Get-PropertyValue $intel "pickup_zone_ids" @()))
    if ($pickupZones.Count -eq 0) { $pickupZones = @((Get-PropertyValue $Tour "pickup_zone_ids" @())) }
    return [pscustomobject]@{
        id = [string](Get-PropertyValue $Tour "id" "")
        name = [string](Get-PropertyValue $Tour "name" "")
        status = Normalize-Key ([string](Get-PropertyValue $Tour "status" "active"))
        price_confirmed = [bool](Get-PropertyValue $pricing "price_confirmed" $false)
        duration_type = [string](Get-PropertyValue $intel "duration_type" "")
        priority = [double](Get-PropertyValue $intel "recommendation_priority" 70)
        pickup_zones = @($pickupZones | ForEach-Object { Normalize-Key ([string]$_) })
        featured_hotels = @((Get-PropertyValue $Tour "featured_hotel_ids" @()))
        family_score = [double](Get-PropertyValue $travelerScores "families" 0)
        relaxation_score = [double](Get-PropertyValue $travelerScores "relaxation" 0)
        adventure_score = [double](Get-PropertyValue $travelerScores "adventure" 0)
    }
}

function Get-ScoreRound1 {
    param([double]$Value)
    # AwayFromZero to match the approved Node.js simulation's round-half-up
    # behavior; .NET's default Math.Round uses banker's rounding (ToEven),
    # which would silently disagree at .x5 midpoints (e.g. 21.25).
    return [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero)
}

function Test-EligibilityV3 {
    param($HotelProfile, $TourProfile)
    $reasons = @()
    if ($TourProfile.status -ne "active") { $reasons += "inactive" }
    if (-not $TourProfile.price_confirmed) { $reasons += "price_not_confirmed" }
    $pickupOk = ($TourProfile.pickup_zones.Count -eq 0) -or (
        (-not [string]::IsNullOrWhiteSpace($HotelProfile.pickup_zone)) -and
        ($TourProfile.pickup_zones -contains $HotelProfile.pickup_zone)
    )
    if (-not $pickupOk) { $reasons += "pickup_mismatch" }
    return [pscustomobject]@{
        eligible = ($reasons.Count -eq 0)
        reasons = $reasons
    }
}

function Get-RankingScoreV3 {
    param($HotelProfile, $TourProfile)

    $b = [ordered]@{}

    $priorityPoints = Get-ScoreRound1 (($TourProfile.priority / 100.0) * 15.0)
    $b.priority = $priorityPoints

    $curatedPoints = $(if ($HotelProfile.featured_tours -contains $TourProfile.id) { 3 } else { 0 })
    $b.curatedBonus = $curatedPoints

    $reciprocalPoints = $(if ($TourProfile.featured_hotels -contains $HotelProfile.id) { 4 } else { 0 })
    $b.reciprocalFeaturedBonus = $reciprocalPoints

    $weights = @(
        @{ w = $HotelProfile.family_weight;    v = $TourProfile.family_score },
        @{ w = $HotelProfile.wellness_weight;   v = $TourProfile.relaxation_score },
        @{ w = $HotelProfile.adventure_weight;  v = $TourProfile.adventure_score }
    )
    $sumWeighted = 0.0
    $sumWeights = 0.0
    foreach ($pair in $weights) {
        if ($pair.w -gt 0) { $sumWeighted += ($pair.v * $pair.w); $sumWeights += $pair.w }
    }
    $weightedFit = 0.0
    $fitPoints = 0.0
    if ($sumWeights -gt 0) {
        $weightedFit = $sumWeighted / $sumWeights
        $fitPoints = Get-ScoreRound1 (($weightedFit / 100.0) * 25.0)
    }
    $b.travelerFit = $fitPoints
    $b.weighted_fit = Get-ScoreRound1 $weightedFit
    $b.family_weight = $HotelProfile.family_weight
    $b.wellness_weight = $HotelProfile.wellness_weight
    $b.adventure_weight = $HotelProfile.adventure_weight

    $durationPoints = $(if ($TourProfile.duration_type -eq "Full Day") { -2 } else { 0 })
    $b.duration = $durationPoints

    $rawScore = $priorityPoints + $fitPoints + $curatedPoints + $reciprocalPoints + $durationPoints
    $finalScore = Get-ScoreRound1 $rawScore
    $b.final = $finalScore

    return [pscustomobject]$b
}

# ---- Load tours once ----
$tourFiles = @(Get-ChildItem -Path $tourDir -Filter "*.json" -File | Sort-Object Name)
if ($tourFiles.Count -eq 0) { throw "No tour JSON files found in $tourDir" }
$TourProfiles = @($tourFiles | ForEach-Object { Get-TourProfileV3 (Read-JsonFile $_.FullName) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_.id) })

# ---- Resolve hotel list ----
$hotelFiles = @()
if ($HotelIds -and $HotelIds.Count -gt 0) {
    foreach ($hid in $HotelIds) {
        $path = Join-Path $hotelDir "$hid.json"
        if (-not (Test-Path $path)) { throw "Hotel master file not found: $path" }
        $hotelFiles += Get-Item $path
    }
} else {
    $hotelFiles = @(Get-ChildItem -Path $hotelDir -Filter "*.json" -File | Where-Object { $_.Name -notmatch '\.v\d+-backup' } | Sort-Object Name)
}

Write-Host ""
Write-Host "Tour Ranking Engine v3 -- B3 Curated+Fit -- $(if ($Write) { 'WRITE MODE' } else { 'DRY-RUN MODE (no files will be modified)' })" -ForegroundColor Cyan

foreach ($hotelFile in $hotelFiles) {
    $hotel = Read-JsonFile $hotelFile.FullName
    $fallbackId = $hotelFile.BaseName
    $hotelProfile = Get-HotelProfileV3 $hotel $fallbackId
    if ([string]::IsNullOrWhiteSpace($hotelProfile.id)) {
        Write-Host "SKIP $($hotelFile.Name): identity.id missing" -ForegroundColor DarkGray
        continue
    }

    $ranking = @()
    $excluded = @()
    foreach ($tourProfile in $TourProfiles) {
        $elig = Test-EligibilityV3 $hotelProfile $tourProfile
        if (-not $elig.eligible) {
            $excluded += [pscustomobject]@{ tour_id = $tourProfile.id; reasons = ($elig.reasons -join ",") }
            continue
        }
        $r = Get-RankingScoreV3 $hotelProfile $tourProfile
        $ranking += [pscustomobject][ordered]@{
            tour_id = $tourProfile.id
            tour_name = $tourProfile.name
            score = $r.final
            priority = $r.priority
            travelerFit = $r.travelerFit
            weighted_fit = $r.weighted_fit
            curatedBonus = $r.curatedBonus
            reciprocalFeaturedBonus = $r.reciprocalFeaturedBonus
            family_weight = $r.family_weight
            wellness_weight = $r.wellness_weight
            adventure_weight = $r.adventure_weight
            duration = $r.duration
        }
    }

    $ranking = @($ranking | Sort-Object @{ Expression = "score"; Descending = $true }, @{ Expression = "tour_name"; Descending = $false })

    Write-Host ""
    Write-Host "--- $($hotelProfile.id) (fam=$($hotelProfile.family_weight) well=$($hotelProfile.wellness_weight) adv=$($hotelProfile.adventure_weight)) eligible=$($ranking.Count) excluded=$($excluded.Count) ---" -ForegroundColor Yellow
    if ($excluded.Count -gt 0) {
        Write-Host ("  excluded: " + (($excluded | ForEach-Object { "$($_.tour_id)[$($_.reasons)]" }) -join ", ")) -ForegroundColor DarkGray
    }
    Write-Host ("{0,-4} {1,-45} {2,6} {3,6} {4,8} {5,8} {6,8} {7,10} {8,6}" -f "Rank","Tour","Score","Prio","TravFit","WFit","Curated","Reciprocal","Dur")
    $rank = 1
    foreach ($item in ($ranking | Select-Object -First 5)) {
        Write-Host ("{0,-4} {1,-45} {2,6} {3,6} {4,8} {5,8} {6,8} {7,10} {8,6}" -f $rank, $item.tour_name.Substring(0,[Math]::Min(45,$item.tour_name.Length)), $item.score, $item.priority, $item.travelerFit, $item.weighted_fit, $item.curatedBonus, $item.reciprocalFeaturedBonus, $item.duration)
        $rank++
    }

    if ($Write) {
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
        $output = [pscustomobject][ordered]@{
            schema_version = "3.0"
            formula = "v3-b3-curated-fit"
            hotel_id = $hotelProfile.id
            generated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            pickup_zone = $hotelProfile.pickup_zone
            total_ranked = $ranking.Count
            excluded = $excluded
            recommendations = $ranking
        }
        $outputPath = Join-Path $outputDir "$($hotelProfile.id)-ranking.json"
        $json = $output | ConvertTo-Json -Depth 15
        [System.IO.File]::WriteAllText($outputPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "WRITTEN: $outputPath" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Tour Ranking Engine v3 complete." -ForegroundColor Cyan

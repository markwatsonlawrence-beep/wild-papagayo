# Tour Ranking Engine v2 -- Minimal Fix V1-CLEAN (validated, approved)
# Single-purpose, auditable implementation of the approved V1-CLEAN ranking
# formula. Does NOT copy the legacy tour-ranking-engine.ps1's binary >=4
# traveler-fit gating or its independent category bonus -- both were
# retired by the architecture audit and the V1-CLEAN simulation.
#
# Usage:
#   .\tour-ranking-engine-v2.ps1                              (dry-run, all hotels)
#   .\tour-ranking-engine-v2.ps1 -HotelIds four-seasons-papagayo   (dry-run, one hotel)
#   .\tour-ranking-engine-v2.ps1 -HotelIds four-seasons-papagayo -Write  (write, one hotel)
#
# Dry-run (no -Write) is the default and never writes anything. Write mode
# requires -HotelIds explicitly -- there is no "-Write all hotels" shortcut.
# Write mode outputs to knowledge\recommendations\rankings-v2\, a directory
# separate from the legacy (known-stale) knowledge\recommendations\rankings\
# so this script can never silently overwrite those artifacts.

param(
    [string[]]$HotelIds,
    [switch]$Write
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$hotelDir = Join-Path $root "knowledge\master\hotels"
$tourDir = Join-Path $root "knowledge\tours"
$outputDir = Join-Path $root "knowledge\recommendations\rankings-v2"

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

function Get-HotelProfileV2 {
    param($Hotel, [string]$FallbackId)
    $identity = Get-PropertyValue $Hotel "identity" $null
    $location = Get-PropertyValue $Hotel "location" $null
    $scores = Get-PropertyValue $Hotel "experience_scores" $null
    $id = [string](Get-PropertyValue $identity "id" "")
    if ([string]::IsNullOrWhiteSpace($id)) { $id = $FallbackId }
    return [pscustomobject]@{
        id = $id
        pickup_zone = Normalize-Key ([string](Get-PropertyValue $location "tour_pickup_zone" ""))
        family_weight = [double](Get-PropertyValue (Get-PropertyValue $scores "families" $null) "score" 0)
        wellness_weight = [double](Get-PropertyValue (Get-PropertyValue $scores "wellness" $null) "score" 0)
        adventure_weight = [double](Get-PropertyValue (Get-PropertyValue $scores "adventure_access" $null) "score" 0)
    }
}

function Get-TourProfileV2 {
    param($Tour)
    $intel = Get-PropertyValue $Tour "intelligence" $null
    $travelerScores = Get-PropertyValue $intel "traveler_scores" $null
    $pickupZones = @((Get-PropertyValue $intel "pickup_zone_ids" @()))
    if ($pickupZones.Count -eq 0) { $pickupZones = @((Get-PropertyValue $Tour "pickup_zone_ids" @())) }
    return [pscustomobject]@{
        id = [string](Get-PropertyValue $Tour "id" "")
        name = [string](Get-PropertyValue $Tour "name" "")
        status = Normalize-Key ([string](Get-PropertyValue $Tour "status" "active"))
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

function Get-RankingScoreV2 {
    param($HotelProfile, $TourProfile)

    $b = [ordered]@{}

    $priorityPoints = Get-ScoreRound1 (($TourProfile.priority / 100.0) * 25.0)
    $b.priority = $priorityPoints

    $pickupPoints = 0
    if (-not [string]::IsNullOrWhiteSpace($HotelProfile.pickup_zone) -and $TourProfile.pickup_zones -contains $HotelProfile.pickup_zone) {
        $pickupPoints = 25
    } elseif ($TourProfile.pickup_zones.Count -eq 0) {
        $pickupPoints = 6
    } else {
        $pickupPoints = -20
    }
    $b.pickup = $pickupPoints

    $featuredPoints = $(if ($TourProfile.featured_hotels -contains $HotelProfile.id) { 8 } else { 0 })
    $b.featured = $featuredPoints

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
        $fitPoints = Get-ScoreRound1 (($weightedFit / 100.0) * 22.0)
    }
    $b.travelerFit = $fitPoints
    $b.weighted_fit = Get-ScoreRound1 $weightedFit
    $b.family_weight = $HotelProfile.family_weight
    $b.wellness_weight = $HotelProfile.wellness_weight
    $b.adventure_weight = $HotelProfile.adventure_weight

    $durationPoints = $(if ($TourProfile.duration_type -eq "Full Day") { -2 } else { 0 })
    $b.duration = $durationPoints

    $inactivePoints = 0
    if ($TourProfile.status -ne "active") { $inactivePoints = -100 }
    $b.inactive = $inactivePoints

    $rawScore = $priorityPoints + $pickupPoints + $featuredPoints + $fitPoints + $durationPoints + $inactivePoints
    $finalScore = [Math]::Max(0.0, [Math]::Min(100.0, (Get-ScoreRound1 $rawScore)))
    $b.final = $finalScore

    return [pscustomobject]$b
}

# ---- Load tours once ----
$tourFiles = @(Get-ChildItem -Path $tourDir -Filter "*.json" -File | Sort-Object Name)
if ($tourFiles.Count -eq 0) { throw "No tour JSON files found in $tourDir" }
$TourProfiles = @($tourFiles | ForEach-Object { Get-TourProfileV2 (Read-JsonFile $_.FullName) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_.id) })

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
Write-Host "Tour Ranking Engine v2 -- Minimal Fix V1-CLEAN -- $(if ($Write) { 'WRITE MODE' } else { 'DRY-RUN MODE (no files will be modified)' })" -ForegroundColor Cyan

foreach ($hotelFile in $hotelFiles) {
    $hotel = Read-JsonFile $hotelFile.FullName
    $fallbackId = $hotelFile.BaseName
    $hotelProfile = Get-HotelProfileV2 $hotel $fallbackId
    if ([string]::IsNullOrWhiteSpace($hotelProfile.id)) {
        Write-Host "SKIP $($hotelFile.Name): identity.id missing" -ForegroundColor DarkGray
        continue
    }

    $ranking = @()
    foreach ($tourProfile in $TourProfiles) {
        $r = Get-RankingScoreV2 $hotelProfile $tourProfile
        $ranking += [pscustomobject][ordered]@{
            tour_id = $tourProfile.id
            tour_name = $tourProfile.name
            score = $r.final
            priority = $r.priority
            pickup = $r.pickup
            featured = $r.featured
            travelerFit = $r.travelerFit
            weighted_fit = $r.weighted_fit
            family_weight = $r.family_weight
            wellness_weight = $r.wellness_weight
            adventure_weight = $r.adventure_weight
            duration = $r.duration
            inactive = $r.inactive
        }
    }

    $ranking = @($ranking | Sort-Object @{ Expression = "score"; Descending = $true }, @{ Expression = "tour_name"; Descending = $false })

    Write-Host ""
    Write-Host "--- $($hotelProfile.id) (fam=$($hotelProfile.family_weight) well=$($hotelProfile.wellness_weight) adv=$($hotelProfile.adventure_weight)) ---" -ForegroundColor Yellow
    Write-Host ("{0,-4} {1,-45} {2,6} {3,6} {4,6} {5,6} {6,8} {7,8} {8,6} {9,6}" -f "Rank","Tour","Score","Prio","Pickup","Feat","TravFit","WFit","Dur","Inact")
    $rank = 1
    foreach ($item in $ranking) {
        Write-Host ("{0,-4} {1,-45} {2,6} {3,6} {4,6} {5,6} {6,8} {7,8} {8,6} {9,6}" -f $rank, $item.tour_name.Substring(0,[Math]::Min(45,$item.tour_name.Length)), $item.score, $item.priority, $item.pickup, $item.featured, $item.travelerFit, $item.weighted_fit, $item.duration, $item.inactive)
        $rank++
    }

    if ($Write) {
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
        $output = [pscustomobject][ordered]@{
            schema_version = "2.0"
            formula = "v1-clean"
            hotel_id = $hotelProfile.id
            generated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            pickup_zone = $hotelProfile.pickup_zone
            total_ranked = $ranking.Count
            recommendations = $ranking
        }
        $outputPath = Join-Path $outputDir "$($hotelProfile.id)-ranking.json"
        $json = $output | ConvertTo-Json -Depth 15
        [System.IO.File]::WriteAllText($outputPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "WRITTEN: $outputPath" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Tour Ranking Engine v2 complete." -ForegroundColor Cyan

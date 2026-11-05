param(
    [string]$HotelId,
    [switch]$All,
    [int]$Top = 10,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$hotelDir = Join-Path $root "knowledge\master\hotels"
$tourDir = Join-Path $root "knowledge\tours"
$outputDir = Join-Path $root "knowledge\recommendations\rankings"

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

function Get-PropertyValue {
    param($Object, [string]$Name, $Default = $null)

    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "JSON file not found: $Path"
    }

    return (
        [System.IO.File]::ReadAllText(
            $Path,
            [System.Text.Encoding]::UTF8
        ) | ConvertFrom-Json
    )
}

function Normalize-Key {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return $Value.Trim().ToLowerInvariant()
}

function Get-HotelProfile {
    param($Hotel)

    $profiles = @((Get-PropertyValue $Hotel "traveler_profiles" @()))
    $scores = Get-PropertyValue $Hotel "experience_scores" $null
    $location = Get-PropertyValue $Hotel "location" $null
    $identity = Get-PropertyValue $Hotel "identity" $null

    return [pscustomobject]@{
        id = [string](Get-PropertyValue $identity "id" "")
        pickup_zone = Normalize-Key ([string](Get-PropertyValue $location "tour_pickup_zone" ""))
        luxury_level = Normalize-Key ([string](Get-PropertyValue $identity "luxury_level" ""))
        traveler_profiles = @($profiles | ForEach-Object { Normalize-Key ([string]$_) })
        family_score = [double](Get-PropertyValue (Get-PropertyValue $scores "families" $null) "score" 0)
        couple_score = [double](Get-PropertyValue (Get-PropertyValue $scores "couples" $null) "score" 0)
        luxury_score = [double](Get-PropertyValue (Get-PropertyValue $scores "luxury" $null) "score" 0)
        wellness_score = [double](Get-PropertyValue (Get-PropertyValue $scores "wellness" $null) "score" 0)
        adventure_score = [double](Get-PropertyValue (Get-PropertyValue $scores "adventure_access" $null) "score" 0)
    }
}

function Get-TourProfile {
    param($Tour)

    $intel = Get-PropertyValue $Tour "intelligence" $null
    $travelerScores = Get-PropertyValue $intel "traveler_scores" $null
    $pickupZones = @((Get-PropertyValue $intel "pickup_zone_ids" @()))

    if ($pickupZones.Count -eq 0) {
        $pickupZones = @((Get-PropertyValue $Tour "pickup_zone_ids" @()))
    }

    return [pscustomobject]@{
        id = [string](Get-PropertyValue $Tour "id" "")
        name = [string](Get-PropertyValue $Tour "name" "")
        status = Normalize-Key ([string](Get-PropertyValue $Tour "status" "active"))
        category = [string](Get-PropertyValue $intel "primary_category" (Get-PropertyValue $Tour "category" ""))
        energy = [string](Get-PropertyValue $intel "energy_level" "Medium")
        duration_type = [string](Get-PropertyValue $intel "duration_type" "")
        priority = [double](Get-PropertyValue $intel "recommendation_priority" 70)
        pickup_zones = @($pickupZones | ForEach-Object { Normalize-Key ([string]$_) })
        featured_hotels = @((Get-PropertyValue $Tour "featured_hotel_ids" @()))
        family_score = [double](Get-PropertyValue $travelerScores "families" 0)
        couple_score = [double](Get-PropertyValue $travelerScores "couples" 0)
        senior_score = [double](Get-PropertyValue $travelerScores "seniors" 0)
        adventure_score = [double](Get-PropertyValue $travelerScores "adventure" 0)
        private_score = [double](Get-PropertyValue $travelerScores "private" 0)
        wildlife_score = [double](Get-PropertyValue $travelerScores "wildlife" 0)
        relaxation_score = [double](Get-PropertyValue $travelerScores "relaxation" 0)
    }
}

function Add-Reason {
    param(
        [System.Collections.Generic.List[string]]$Reasons,
        [string]$Text
    )

    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        $Reasons.Add($Text)
    }
}

function Get-RankingScore {
    param($HotelProfile, $TourProfile)

    $score = 0.0
    $reasons = New-Object 'System.Collections.Generic.List[string]'

    $priorityPoints = [Math]::Round(($TourProfile.priority / 100.0) * 25.0, 1)
    $score += $priorityPoints
    Add-Reason $reasons "High recommendation priority"

    if (
        -not [string]::IsNullOrWhiteSpace($HotelProfile.pickup_zone) -and
        $TourProfile.pickup_zones -contains $HotelProfile.pickup_zone
    ) {
        $score += 25
        Add-Reason $reasons "Pickup compatible with $($HotelProfile.pickup_zone)"
    }
    elseif ($TourProfile.pickup_zones.Count -eq 0) {
        $score += 6
        Add-Reason $reasons "Pickup zone requires review"
    }
    else {
        $score -= 20
        Add-Reason $reasons "Pickup zone mismatch"
    }

    if ($TourProfile.featured_hotels -contains $HotelProfile.id) {
        $score += 8
        Add-Reason $reasons "Previously curated for this hotel"
    }

    $fitValues = @()

    if ($HotelProfile.family_score -ge 4) {
        $fitValues += $TourProfile.family_score
        if ($TourProfile.family_score -ge 85) {
            Add-Reason $reasons "Strong family fit"
        }
    }

    if ($HotelProfile.couple_score -ge 4) {
        $fitValues += $TourProfile.couple_score
        if ($TourProfile.couple_score -ge 85) {
            Add-Reason $reasons "Strong couples fit"
        }
    }

    if ($HotelProfile.luxury_score -ge 4) {
        $fitValues += $TourProfile.private_score
        if ($TourProfile.private_score -ge 85) {
            Add-Reason $reasons "Strong private fit"
        }
    }

    if ($HotelProfile.wellness_score -ge 4) {
        $fitValues += $TourProfile.relaxation_score
        if ($TourProfile.relaxation_score -ge 80) {
            Add-Reason $reasons "Supports a relaxed stay"
        }
    }

    if ($HotelProfile.adventure_score -ge 4) {
        $fitValues += $TourProfile.adventure_score
        if ($TourProfile.adventure_score -ge 80) {
            Add-Reason $reasons "Strong adventure fit"
        }
    }

    if ($fitValues.Count -gt 0) {
        $avgFit = ($fitValues | Measure-Object -Average).Average
        $score += [Math]::Round(($avgFit / 100.0) * 22.0, 1)
    }

    switch -Regex ($TourProfile.category) {
        "Nature|Wildlife" {
            $score += 10
            Add-Reason $reasons "Nature and wildlife value"
        }
        "Ocean" {
            $score += 9
            Add-Reason $reasons "Ocean experience balance"
        }
        "Volcano|Wellness" {
            $score += 8
            Add-Reason $reasons "Volcano or wellness value"
        }
        "Adventure|Water Adventure" {
            $score += 7
            Add-Reason $reasons "Adventure value"
        }
        default {
            $score += 5
        }
    }

    if ($TourProfile.duration_type -eq "Full Day") {
        $score -= 2
    }

    if ($TourProfile.status -ne "active") {
        $score -= 100
        Add-Reason $reasons "Tour is not active"
    }

    $score = [Math]::Max(0, [Math]::Min(100, [Math]::Round($score, 1)))

    return [pscustomobject]@{
        score = $score
        reasons = @($reasons | Select-Object -Unique)
    }
}

$hotelFiles = @()

if ($All) {
    $hotelFiles = @(Get-ChildItem -Path $hotelDir -Filter "*.json" -File | Sort-Object Name)
}
elseif (-not [string]::IsNullOrWhiteSpace($HotelId)) {
    $path = Join-Path $hotelDir "$HotelId.json"
    if (-not (Test-Path $path)) {
        throw "Hotel master file not found: $path"
    }
    $hotelFiles = @(Get-Item $path)
}
else {
    throw "Use -All or -HotelId <id>."
}

$tourFiles = @(Get-ChildItem -Path $tourDir -Filter "*.json" -File | Sort-Object Name)

if ($tourFiles.Count -eq 0) {
    throw "No tour JSON files found in $tourDir"
}

foreach ($hotelFile in $hotelFiles) {
    $hotel = Read-JsonFile $hotelFile.FullName
    $hotelProfile = Get-HotelProfile $hotel

    if ([string]::IsNullOrWhiteSpace($hotelProfile.id)) {
        Write-Host "SKIP $($hotelFile.Name): identity.id missing (backup or legacy file)" -ForegroundColor DarkGray
        continue
    }

    $ranking = @()

    foreach ($tourFile in $tourFiles) {
        $tour = Read-JsonFile $tourFile.FullName
        $tourProfile = Get-TourProfile $tour

        if ([string]::IsNullOrWhiteSpace($tourProfile.id)) {
            continue
        }

        $rank = Get-RankingScore $hotelProfile $tourProfile

        $ranking += [pscustomobject][ordered]@{
            tour_id = $tourProfile.id
            tour_name = $tourProfile.name
            score = $rank.score
            category = $tourProfile.category
            energy_level = $tourProfile.energy
            duration_type = $tourProfile.duration_type
            pickup_compatible = ($tourProfile.pickup_zones -contains $hotelProfile.pickup_zone)
            reasons = $rank.reasons
        }
    }

    $ranking = @(
        $ranking |
        Sort-Object `
            @{ Expression = "score"; Descending = $true },
            @{ Expression = "tour_name"; Descending = $false }
    )

    if ($Top -gt 0) {
        $ranking = @($ranking | Select-Object -First $Top)
    }

    $output = [pscustomobject][ordered]@{
        schema_version = "1.0"
        hotel_id = $hotelProfile.id
        generated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        pickup_zone = $hotelProfile.pickup_zone
        total_ranked = $ranking.Count
        recommendations = $ranking
    }

    $outputPath = Join-Path $outputDir "$($hotelProfile.id)-ranking.json"

    if ((Test-Path $outputPath) -and -not $Force) {
        Write-Host "OVERWRITE $($hotelProfile.id): ranking already exists" -ForegroundColor Yellow
    }

    $json = $output | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText(
        $outputPath,
        $json,
        (New-Object System.Text.UTF8Encoding($false))
    )

    Write-Host ""
    Write-Host "Tour ranking generated: $($hotelProfile.id)" -ForegroundColor Cyan
    Write-Host "Output: $outputPath"
    Write-Host "Top recommendations:"

    foreach ($item in ($ranking | Select-Object -First 5)) {
        Write-Host ("  {0,5}  {1}" -f $item.score, $item.tour_name) -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Tour Ranking Engine complete." -ForegroundColor Cyan

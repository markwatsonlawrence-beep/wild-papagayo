# WEP 2.1 - Smart Itinerary Engine
# Generates a hotel-specific suggested_stay from tour intelligence profiles.
# Writes the result directly into the legacy hotel JSON (knowledge/hotels/).
# Run tour-profile-enricher.ps1 first if tours haven't been enriched yet.
#
# Usage:
#   .\smart-itinerary-engine.ps1 -HotelId four-seasons-papagayo
#   .\smart-itinerary-engine.ps1 -HotelId andaz-costa-rica -Days 5
#   .\smart-itinerary-engine.ps1 -HotelId waldorf-astoria-costa-rica -DryRun
#   .\smart-itinerary-engine.ps1 -All           (run all hotels)

param(
    [string]$HotelId = "",
    [int]$Days       = 7,
    [switch]$All,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

. (Join-Path $root "engine\itinerary\SmartItinerary.Core.ps1")

# ── Load all tours once ───────────────────────────────────────────────────────

$toursDir = Join-Path $root "knowledge\tours"
$AllTours = @(Get-ChildItem $toursDir -Filter "*.json" | ForEach-Object {
    $raw = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    $raw | ConvertFrom-Json
})

$enrichedCount = ($AllTours | Where-Object { $null -ne (Get-TourItineraryProfile $_) }).Count
if ($enrichedCount -eq 0) {
    Write-Host ""
    Write-Host "WARNING: No tours have itinerary profiles yet." -ForegroundColor Yellow
    Write-Host "Run  .\tour-profile-enricher.ps1  first, then re-run this script." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# ── Resolve hotel list ────────────────────────────────────────────────────────

$hotelsDir = Join-Path $root "knowledge\hotels"

if ($All) {
    $hotelFiles = @(Get-ChildItem $hotelsDir -Filter "*.json")
} elseif ($HotelId -ne "") {
    $path = Join-Path $hotelsDir "$HotelId.json"
    if (-not (Test-Path $path)) {
        Write-Host "Hotel not found: $path" -ForegroundColor Red
        exit 1
    }
    $hotelFiles = @(Get-Item $path)
} else {
    Write-Host ""
    Write-Host "Usage: .\smart-itinerary-engine.ps1 -HotelId <id> [-Days N] [-DryRun]" -ForegroundColor Yellow
    Write-Host "       .\smart-itinerary-engine.ps1 -All [-Days N] [-DryRun]"           -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# ── Process each hotel ────────────────────────────────────────────────────────

function Format-DayType {
    param([string]$Type)
    switch ($Type) {
        "arrival"    { return "[Arrival  ]" }
        "departure"  { return "[Departure]" }
        "resort"     { return "[Resort   ]" }
        "free"       { return "[Free Day ]" }
        "nature"     { return "[Nature   ]" }
        "wildlife"   { return "[Wildlife ]" }
        "adventure"  { return "[Adventure]" }
        "waterfall"  { return "[Waterfall]" }
        "rainforest" { return "[Rainfrst ]" }
        "ocean"      { return "[Ocean    ]" }
        "wellness"   { return "[Wellness ]" }
        "cultural"   { return "[Cultural ]" }
        default      { return "[$Type]"     }
    }
}

$totalProcessed = 0

Write-Host ""
Write-Host "------------------------------------------------" -ForegroundColor Cyan
Write-Host " WEP 2.1  Smart Itinerary Engine" -ForegroundColor Cyan
Write-Host " Tours loaded: $($AllTours.Count)  |  Enriched: $enrichedCount" -ForegroundColor DarkCyan
Write-Host "------------------------------------------------" -ForegroundColor Cyan

foreach ($file in $hotelFiles) {
    $raw   = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $hotel = $raw | ConvertFrom-Json

    $hotelId   = [string]$hotel.PSObject.Properties['id'].Value
    $hotelName = [string]$hotel.PSObject.Properties['name'].Value
    $zone      = [string]$hotel.PSObject.Properties['tour_pickup_zone'].Value

    # Determine days: use template's suggested_stay length if set, else $Days param
    $stayDays = $Days

    # Count tours eligible for this zone before running
    $eligibleCount = ($AllTours | Where-Object { Test-TourEligible $_ $zone $stayDays }).Count

    Write-Host ""
    Write-Host "  Hotel : $hotelName" -ForegroundColor White
    Write-Host "  Zone  : $zone  |  Stay: $stayDays days  |  Eligible tours: $eligibleCount"
    Write-Host ""

    $itinerary = Build-SmartItinerary -Hotel $hotel -AllTours $AllTours -DurationDays $stayDays

    # Print schedule
    foreach ($day in $itinerary) {
        $typeLabel = Format-DayType ([string]$day.type)
        $tourLabel = ""
        $tidProp   = $day.PSObject.Properties['tour_id']
        if ($null -ne $tidProp -and $tidProp.Value -ne "") {
            $tourLabel = "  [" + [string]$tidProp.Value + "]"
        }
        Write-Host ("    Day {0,-2} {1,-18} {2}{3}" -f $day.day, $typeLabel, $day.title, $tourLabel)
    }

    Write-Host ""

    if ($DryRun) {
        Write-Host "  [DRY RUN] No changes saved for $hotelId" -ForegroundColor Yellow
        continue
    }

    # Strip tour_id from saved JSON (internal scheduling field, not needed in template)
    $cleanItinerary = @($itinerary | ForEach-Object {
        $entry = [PSCustomObject]@{
            day         = $_.day
            title       = $_.title
            description = $_.description
        }
        $entry
    })

    $hotel | Add-Member -NotePropertyName 'suggested_stay' -NotePropertyValue $cleanItinerary -Force

    $json = $hotel | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($file.FullName, $json, [System.Text.UTF8Encoding]::new($false))

    Write-Host "  [SAVED] $($file.Name)" -ForegroundColor Green
    $totalProcessed++
}

Write-Host ""
Write-Host "------------------------------------------------" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host " Dry run complete. No files modified." -ForegroundColor Yellow
} else {
    Write-Host (" Hotels updated: {0}" -f $totalProcessed) -ForegroundColor Green
    if ($totalProcessed -gt 0) {
        Write-Host " Run .\wild-engine.ps1 to rebuild hotel pages." -ForegroundColor DarkCyan
    }
}
Write-Host "------------------------------------------------" -ForegroundColor Cyan
Write-Host ""

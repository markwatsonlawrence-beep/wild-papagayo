# ============================================================
# Wild Papagayo - Hotel Reviews Finder v1.0
# Uses the Google Places API (Text Search + Place Details, New)
# to pull each hotel's REAL Google rating, review count, and a
# few real guest reviews (author, rating, text). Replaces the
# generic "Perfect N-day stay" itinerary block on hotel pages --
# which was redundant with the tour recommendations section --
# with genuine guest sentiment instead.
# Usage: .\hotel-reviews-finder.ps1 [-HotelId "hotel-belmar"]
# Requires GOOGLE_PLACES_API_KEY in wild-papagayo\.env
# ============================================================

[CmdletBinding()]
param(
    [string]$HotelId
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Read-EnvFile {
    param([string]$Path)
    $vars = @{}
    if (-not (Test-Path $Path)) { return $vars }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') { $vars[$Matches[1]] = $Matches[2].Trim() }
    }
    return $vars
}
$envVars = Read-EnvFile (Join-Path $root '.env')
$apiKey = $envVars['GOOGLE_PLACES_API_KEY']
if ([string]::IsNullOrWhiteSpace($apiKey)) { $apiKey = $env:GOOGLE_PLACES_API_KEY }
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'GOOGLE_PLACES_API_KEY not found. Add it to wild-papagayo\.env' }

$hotelsDir = Join-Path $root 'knowledge\master\hotels'
$files = if ($HotelId) {
    @(Join-Path $hotelsDir "$HotelId.json")
} else {
    Get-ChildItem $hotelsDir -Filter '*.json' -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' } | Select-Object -ExpandProperty FullName
}

foreach ($file in $files) {
    if (-not (Test-Path $file)) { Write-Host "Skip (not found): $file" -ForegroundColor Yellow; continue }
    $h = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $name = if ($h.identity.official_name) { [string]$h.identity.official_name } else { [string]$h.identity.display_name }
    Write-Host "Searching Google for: $name..." -ForegroundColor Cyan

    $searchHeaders = @{
        'Content-Type' = 'application/json'
        'X-Goog-Api-Key' = $apiKey
        'X-Goog-FieldMask' = 'places.id,places.displayName,places.rating,places.userRatingCount'
    }
    $searchBody = @{ textQuery = "$name, Costa Rica" } | ConvertTo-Json

    try {
        $searchResponse = Invoke-RestMethod -Uri 'https://places.googleapis.com/v1/places:searchText' -Method Post -Headers $searchHeaders -Body $searchBody -TimeoutSec 30
    } catch {
        Write-Host "  Search failed: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }

    $place = $searchResponse.places | Select-Object -First 1
    if (-not $place) { Write-Host "  No Google listing found." -ForegroundColor Yellow; continue }

    $detailHeaders = @{
        'X-Goog-Api-Key' = $apiKey
        'X-Goog-FieldMask' = 'rating,userRatingCount,reviews'
    }
    try {
        $details = Invoke-RestMethod -Uri "https://places.googleapis.com/v1/places/$($place.id)" -Method Get -Headers $detailHeaders -TimeoutSec 30
    } catch {
        Write-Host "  Details fetch failed: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }

    $topReviews = @($details.reviews | Where-Object { $_.rating -ge 4 -and $_.text.text } | Select-Object -First 3 | ForEach-Object {
        $text = [string]$_.text.text
        if ($text.Length -gt 320) { $text = $text.Substring(0, 317).Trim() + '...' }
        [ordered]@{
            author = [string]$_.authorAttribution.displayName
            rating = $_.rating
            text = $text
            relative_time = [string]$_.relativePublishTimeDescription
        }
    })

    $googleReviews = [ordered]@{
        rating = $details.rating
        review_count = $details.userRatingCount
        reviews = $topReviews
        source = "Google Places API, fetched $(Get-Date -Format 'yyyy-MM-dd')"
    }

    $h | Add-Member -NotePropertyName 'google_reviews' -NotePropertyValue $googleReviews -Force
    $json = $h | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($file, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Saved: $($details.rating.ToString([System.Globalization.CultureInfo]::InvariantCulture))/5 ($($details.userRatingCount) reviews), $($topReviews.Count) quotes" -ForegroundColor Green
}
Write-Host ''
Write-Host 'Done. Reviews sourced live from Google Places.' -ForegroundColor DarkGray

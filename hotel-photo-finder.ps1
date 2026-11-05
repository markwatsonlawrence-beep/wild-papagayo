# ============================================================
# Wild Papagayo - Hotel Photo Finder v1.0
# Downloads a real cover photo for each hotel from Google Places
# (New) API, replacing the generic stock "temporary_placeholder"
# hero image with an actual photo of the property.
# Usage: .\hotel-photo-finder.ps1 [-HotelId "hotel-belmar"]
# Requires GOOGLE_PLACES_API_KEY in wild-papagayo\.env (must have
# "Places API (New)" in its restrictions)
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

$imagesDir = Join-Path $root 'images'

function Get-PlacePhotos {
    param([string]$Query, [string]$ApiKey)
    $headers = @{
        'Content-Type' = 'application/json'
        'X-Goog-Api-Key' = $ApiKey
        'X-Goog-FieldMask' = 'places.id,places.displayName,places.photos'
    }
    $body = @{ textQuery = $Query } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri 'https://places.googleapis.com/v1/places:searchText' -Method Post -Headers $headers -Body $body -TimeoutSec 30
    return $response.places | Select-Object -First 1
}

function Save-PlacePhoto {
    param([string]$PhotoName, [string]$ApiKey, [string]$OutFile)
    $mediaUrl = "https://places.googleapis.com/v1/$PhotoName/media?maxWidthPx=1600&skipHttpRedirect=true&key=$ApiKey"
    $meta = Invoke-RestMethod -Uri $mediaUrl -Method Get -TimeoutSec 30
    if (-not $meta.photoUri) { throw 'No photoUri returned' }
    Invoke-WebRequest -Uri $meta.photoUri -OutFile $OutFile -TimeoutSec 60 | Out-Null
}

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
    $slug = [string]$h.identity.slug

    Write-Host "Locating photos: $name..." -ForegroundColor Cyan
    try {
        $place = Get-PlacePhotos -Query "$name, Costa Rica" -ApiKey $apiKey
    } catch {
        Write-Host "  Search failed: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
    if (-not $place -or -not $place.photos -or @($place.photos).Count -eq 0) {
        Write-Host "  No photos found for $name." -ForegroundColor Yellow
        continue
    }

    $photo = @($place.photos) | Select-Object -First 1
    $outFile = Join-Path $imagesDir "$slug-hero.jpg"
    try {
        Save-PlacePhoto -PhotoName $photo.name -ApiKey $apiKey -OutFile $outFile
    } catch {
        Write-Host "  Photo download failed: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }

    $category = [string]$h.identity.category
    $locationLabel = [string]$h.location.location_label
    $altText = if ($category -and $locationLabel) { "$name, a $category in $locationLabel, Costa Rica" }
               elseif ($locationLabel) { "$name in $locationLabel, Costa Rica" }
               else { "$name, Costa Rica" }

    $h.gallery.hero_image = "images/$slug-hero.jpg"
    $h.gallery.hero_image_alt = $altText
    $h.gallery.hero_image_status = "google_places_photo"

    $json = $h | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($file, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Saved: images/$slug-hero.jpg" -ForegroundColor Green
}
Write-Host ''
Write-Host 'Done. Real hotel photos downloaded from Google Places.' -ForegroundColor DarkGray

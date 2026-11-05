# ============================================================
# Wild Papagayo - Destination Photo Finder v1.0
# Downloads a real cover photo for a destination from Google
# Places (New) API, replacing the generic stock placeholder
# hero image ("luxury-costa-rica-tours-hero.webp") that
# destination-import-url.ps1 sets by default.
# Usage: .\destination-photo-finder.ps1 [-DestinationId "monteverde"]
# Requires GOOGLE_PLACES_API_KEY in wild-papagayo\.env (must have
# "Places API (New)" in its restrictions)
# ============================================================

[CmdletBinding()]
param(
    [string]$DestinationId
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
    $mediaUrl = "https://places.googleapis.com/v1/$PhotoName/media?maxWidthPx=1600&skipHttpRedirect=true&key=$apiKey"
    $meta = Invoke-RestMethod -Uri $mediaUrl -Method Get -TimeoutSec 30
    if (-not $meta.photoUri) { throw 'No photoUri returned' }
    Invoke-WebRequest -Uri $meta.photoUri -OutFile $OutFile -TimeoutSec 60 | Out-Null
}

$destinationsDir = Join-Path $root 'knowledge\destinations'
$files = if ($DestinationId) {
    @(Join-Path $destinationsDir "$DestinationId.json")
} else {
    Get-ChildItem $destinationsDir -Filter '*.json' -File | Select-Object -ExpandProperty FullName
}

foreach ($file in $files) {
    if (-not (Test-Path $file)) { Write-Host "Skip (not found): $file" -ForegroundColor Yellow; continue }
    $d = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $name = [string]$d.name
    $slug = [string]$d.id

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

    $d.hero_image = "images/$slug-hero.jpg"
    $json = $d | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($file, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Saved: images/$slug-hero.jpg" -ForegroundColor Green
}
Write-Host ''
Write-Host 'Done. Real destination photos downloaded from Google Places.' -ForegroundColor DarkGray

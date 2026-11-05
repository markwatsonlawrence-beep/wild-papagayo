# ============================================================
# Wild Papagayo - Hotel Address Finder v1.0
# Uses Google Places (Text Search) to fetch the real formatted
# street address for each hotel, so the "Where you'll be" section
# can show a real written address next to the map instead of just
# the destination name and a pin.
# Usage: .\hotel-address-finder.ps1 [-HotelId "hotel-belmar"]
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

function Get-PlaceAddress {
    param([string]$Query, [string]$ApiKey)
    $headers = @{
        'Content-Type' = 'application/json'
        'X-Goog-Api-Key' = $ApiKey
        'X-Goog-FieldMask' = 'places.location,places.formattedAddress,places.displayName'
    }
    $body = @{ textQuery = $Query } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri 'https://places.googleapis.com/v1/places:searchText' -Method Post -Headers $headers -Body $body -TimeoutSec 30
    return $response.places | Select-Object -First 1
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

    Write-Host "Locating address: $name..." -ForegroundColor Cyan
    try {
        $place = Get-PlaceAddress -Query "$name, Costa Rica" -ApiKey $apiKey
    } catch {
        Write-Host "  Search failed: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
    if (-not $place -or -not $place.formattedAddress) {
        Write-Host "  No formatted address found for $name." -ForegroundColor Yellow
        continue
    }

    $h.location | Add-Member -MemberType NoteProperty -Name 'formatted_address' -Value ([string]$place.formattedAddress) -Force

    $json = $h | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($file, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Saved: $($place.formattedAddress)" -ForegroundColor Green
}
Write-Host ''
Write-Host 'Done. Real formatted addresses saved from Google Places.' -ForegroundColor DarkGray

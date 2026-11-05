# ============================================================
# Wild Papagayo - Hotel Transfer Time Finder v1.0
# Uses Google Places (to geocode the hotel) + Routes API (to
# compute a real driving route) to replace the static, hand-
# guessed "35-50 minutes" transfer estimate with an actual
# distance and drive time from the real airport to the real
# hotel location.
# Usage: .\hotel-transfer-time-finder.ps1 [-HotelId "hotel-belmar"]
# Requires GOOGLE_PLACES_API_KEY in wild-papagayo\.env (must have
# both "Places API (New)" and "Routes API" in its restrictions)
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

# Real airport coordinates, geocoded once via Places API.
$airportCoords = @{
    'lir' = @{ lat = 10.600985200000002; lng = -85.5359972;              name = 'Daniel Oduber Quiros International Airport (LIR)' }
    'sjo' = @{ lat = 9.9981657;          lng = -84.204760499999992;      name = 'Juan Santamaria International Airport (SJO)' }
}

function Get-PlaceLocation {
    param([string]$Query, [string]$ApiKey)
    $headers = @{
        'Content-Type' = 'application/json'
        'X-Goog-Api-Key' = $ApiKey
        'X-Goog-FieldMask' = 'places.location,places.displayName'
    }
    $body = @{ textQuery = $Query } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri 'https://places.googleapis.com/v1/places:searchText' -Method Post -Headers $headers -Body $body -TimeoutSec 30
    return $response.places | Select-Object -First 1
}

function Get-DriveRoute {
    param([double]$OriginLat, [double]$OriginLng, [double]$DestLat, [double]$DestLng, [string]$ApiKey)
    $headers = @{
        'Content-Type' = 'application/json'
        'X-Goog-Api-Key' = $ApiKey
        'X-Goog-FieldMask' = 'routes.duration,routes.distanceMeters'
    }
    $body = @{
        origin = @{ location = @{ latLng = @{ latitude = $OriginLat; longitude = $OriginLng } } }
        destination = @{ location = @{ latLng = @{ latitude = $DestLat; longitude = $DestLng } } }
        travelMode = 'DRIVE'
    } | ConvertTo-Json -Depth 5
    return Invoke-RestMethod -Uri 'https://routes.googleapis.com/directions/v2:computeRoutes' -Method Post -Headers $headers -Body $body -TimeoutSec 30
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
    $airportId = ([string]$h.location.airport_id).ToLowerInvariant()

    if (-not $airportCoords.ContainsKey($airportId)) {
        Write-Host "Skip $name -- unknown airport_id '$airportId'" -ForegroundColor Yellow
        continue
    }
    $airport = $airportCoords[$airportId]

    Write-Host "Locating: $name..." -ForegroundColor Cyan
    try {
        $place = Get-PlaceLocation -Query "$name, Costa Rica" -ApiKey $apiKey
    } catch {
        Write-Host "  Geocoding failed: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
    if (-not $place -or -not $place.location) { Write-Host "  Could not geocode hotel location." -ForegroundColor Yellow; continue }

    if (-not $h.location.PSObject.Properties['coordinates']) {
        $h.location | Add-Member -MemberType NoteProperty -Name 'coordinates' -Value ([ordered]@{}) -Force
    }
    $h.location.coordinates = [ordered]@{ lat = $place.location.latitude; lng = $place.location.longitude }

    try {
        $route = Get-DriveRoute -OriginLat $airport.lat -OriginLng $airport.lng -DestLat $place.location.latitude -DestLng $place.location.longitude -ApiKey $apiKey
    } catch {
        $errBody = ''
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $errBody = $reader.ReadToEnd()
        }
        Write-Host "  Route request failed: $($_.Exception.Message) $errBody" -ForegroundColor Red
        continue
    }

    $routeResult = $route.routes | Select-Object -First 1
    if (-not $routeResult) { Write-Host "  No route found." -ForegroundColor Yellow; continue }

    $seconds = [int]([string]$routeResult.duration -replace 's$', '')
    $minutes = [Math]::Round($seconds / 60.0)
    $km = [Math]::Round($routeResult.distanceMeters / 1000.0, 1)
    # Present as a realistic range: +/-10% around the real drive time, since actual
    # time varies with traffic -- more honest than a single exact-looking number.
    $minRange = [Math]::Max(1, [Math]::Round($minutes * 0.9))
    $maxRange = [Math]::Round($minutes * 1.15)

    $h.location.transfer.min = $minRange
    $h.location.transfer.max = $maxRange
    $h.location.transfer.label = "Approximately $minRange-$maxRange minutes ($km km) by private transfer from $($airport.name), based on real driving distance."
    $h.location.transfer.source_type = "google_routes_api"

    # Also compute the route from the OTHER airport, so hotel pages can show
    # both LIR and SJO transfer options -- guests often fly into either one.
    $otherAirportId = ($airportCoords.Keys | Where-Object { $_ -ne $airportId }) | Select-Object -First 1
    if (-not $h.location.PSObject.Properties['transfer_by_airport']) {
        $h.location | Add-Member -MemberType NoteProperty -Name 'transfer_by_airport' -Value ([ordered]@{}) -Force
    }
    $byAirport = [ordered]@{}
    $byAirport[$airportId] = [ordered]@{ min = $minRange; max = $maxRange; km = $km; airport_name = $airport.name }
    if ($otherAirportId -and $airportCoords.ContainsKey($otherAirportId)) {
        $otherAirport = $airportCoords[$otherAirportId]
        try {
            $otherRoute = Get-DriveRoute -OriginLat $otherAirport.lat -OriginLng $otherAirport.lng -DestLat $place.location.latitude -DestLng $place.location.longitude -ApiKey $apiKey
            $otherResult = $otherRoute.routes | Select-Object -First 1
            if ($otherResult) {
                $otherSeconds = [int]([string]$otherResult.duration -replace 's$', '')
                $otherMinutes = [Math]::Round($otherSeconds / 60.0)
                $otherKm = [Math]::Round($otherResult.distanceMeters / 1000.0, 1)
                $otherMinRange = [Math]::Max(1, [Math]::Round($otherMinutes * 0.9))
                $otherMaxRange = [Math]::Round($otherMinutes * 1.15)
                $byAirport[$otherAirportId] = [ordered]@{ min = $otherMinRange; max = $otherMaxRange; km = $otherKm; airport_name = $otherAirport.name }
            }
        } catch {
            Write-Host "  Secondary airport route failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    $h.location.transfer_by_airport = $byAirport

    $json = $h | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($file, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Saved: $minRange-$maxRange min ($km km) from $airportId (+ secondary airport)" -ForegroundColor Green
}
Write-Host ''
Write-Host 'Done. Transfer times computed from real driving routes.' -ForegroundColor DarkGray

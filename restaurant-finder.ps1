# ============================================================
# Wild Papagayo - Restaurant Finder v1.1
# Uses the Google Places API (Text Search, New) to find REAL,
# currently-operating restaurants per DESTINATION (not per hotel
# -- "restaurants near [hotel name]" returns near-nothing since
# Google reads it too literally; "best restaurants in [town]"
# returns a proper real list). Only restaurants rated 4.0+ with
# 10+ reviews are kept. Hotel pages reuse this same destination
# list rather than making a separate API call per hotel.
#
# v1.1: for rural/low-density destinations (national parks, ranch
# areas like Rincon de la Vieja) a bare text query has too few real
# local matches and Google drifts to loosely-related results from
# across the whole province (Tamarindo, Los Pargos, etc., 60km+
# away). Fixed by geocoding the destination first, biasing the
# search to a radius around it, and hard-filtering out any result
# whose real distance from the destination exceeds $MaxDistanceKm.
# Usage: .\restaurant-finder.ps1 [-DestinationId "monteverde"]
# Requires GOOGLE_PLACES_API_KEY in wild-papagayo\.env
# ============================================================

[CmdletBinding()]
param(
    [string]$DestinationId,
    [double]$MaxDistanceKm = 20
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

function Get-PropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Get-HaversineKm {
    param([double]$Lat1, [double]$Lng1, [double]$Lat2, [double]$Lng2)
    $R = 6371.0
    $dLat = ($Lat2 - $Lat1) * [Math]::PI / 180
    $dLng = ($Lng2 - $Lng1) * [Math]::PI / 180
    $a = [Math]::Sin($dLat/2) * [Math]::Sin($dLat/2) + [Math]::Cos($Lat1 * [Math]::PI / 180) * [Math]::Cos($Lat2 * [Math]::PI / 180) * [Math]::Sin($dLng/2) * [Math]::Sin($dLng/2)
    $c = 2 * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1-$a))
    return $R * $c
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
    Write-Host "Searching restaurants in: $name..." -ForegroundColor Cyan

    try {
        $center = Get-PlaceLocation -Query "$name, Costa Rica" -ApiKey $apiKey
        if (-not $center -or -not $center.location) {
            # Some beach towns (e.g. Samara) only resolve with the "Playa" prefix
            # Google's index actually uses -- retry once before giving up.
            $center = Get-PlaceLocation -Query "Playa $name, Costa Rica" -ApiKey $apiKey
        }
    } catch {
        Write-Host "  Geocoding failed: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
    if (-not $center -or -not $center.location) {
        Write-Host "  Could not geocode destination -- skipping (no location anchor to filter against)." -ForegroundColor Yellow
        continue
    }
    $centerLat = $center.location.latitude
    $centerLng = $center.location.longitude

    # Some destinations (remote park/volcano access points like Rincon de la
    # Vieja) have no real dining scene of their own -- guests actually eat in
    # the nearest real town. Let the destination JSON override the search
    # query with that town's name via "restaurant_query_override" while still
    # filtering by real distance from the destination's own geocoded center,
    # so results stay honestly close even though the query text points
    # elsewhere.
    $queryOverride = [string](Get-PropertyValue $d 'restaurant_query_override' '')
    $query = if ($queryOverride) { "best restaurants in $queryOverride, Costa Rica" } else { "best restaurants in $name, Costa Rica" }
    $url = "https://places.googleapis.com/v1/places:searchText"
    $headers = @{
        'Content-Type' = 'application/json'
        'X-Goog-Api-Key' = $apiKey
        'X-Goog-FieldMask' = 'places.displayName,places.rating,places.userRatingCount,places.formattedAddress,places.types,places.location'
    }
    $body = @{
        textQuery = $query
        locationBias = @{ circle = @{ center = @{ latitude = $centerLat; longitude = $centerLng }; radius = ($MaxDistanceKm * 1000) } }
    } | ConvertTo-Json -Depth 6

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -TimeoutSec 30
    } catch {
        $errBody = ''
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $errBody = $reader.ReadToEnd()
        }
        Write-Host "  API request failed: $($_.Exception.Message) $errBody" -ForegroundColor Red
        continue
    }

    $places = @($response.places)
    # Google's text search sometimes returns parks/tours/hotels for queries like
    # "restaurants in X", and locationBias only nudges ranking rather than
    # strictly filtering -- so a hard distance check from the geocoded center is
    # what actually keeps rural/low-density destinations from pulling in
    # restaurants an hour+ away. Reject anything without a location too, since
    # it can't be verified as nearby.
    $results = @($places | Where-Object {
        $_.rating -ge 4.0 -and $_.userRatingCount -ge 10 -and
        (@($_.types) -contains 'restaurant' -or @($_.types) -contains 'food' -or @($_.types) -contains 'bar') -and
        $_.location -and
        (Get-HaversineKm -Lat1 $centerLat -Lng1 $centerLng -Lat2 $_.location.latitude -Lng2 $_.location.longitude) -le $MaxDistanceKm
    } | Sort-Object -Property rating -Descending | Select-Object -First 8)

    if ($results.Count -eq 0) {
        Write-Host "  No qualifying restaurants found within ${MaxDistanceKm}km (rating >= 4.0, 10+ reviews)." -ForegroundColor Yellow
        $d.PSObject.Properties.Remove('restaurants')
        $d | Add-Member -NotePropertyName 'restaurants_source' -NotePropertyValue "Google Places API, fetched $(Get-Date -Format 'yyyy-MM-dd') -- no restaurants within ${MaxDistanceKm}km found" -Force
        $json = $d | ConvertTo-Json -Depth 15
        [System.IO.File]::WriteAllText($file, $json, [System.Text.UTF8Encoding]::new($false))
        continue
    }

    $restaurants = @($results | ForEach-Object {
        [ordered]@{
            name = [string]$_.displayName.text
            rating = $_.rating
            review_count = $_.userRatingCount
            address = [string]$_.formattedAddress
            types = @($_.types | Where-Object { $_ -notin @('point_of_interest', 'establishment', 'food') } | Select-Object -First 3)
        }
    })

    $d | Add-Member -NotePropertyName 'restaurants' -NotePropertyValue $restaurants -Force
    $d | Add-Member -NotePropertyName 'restaurants_source' -NotePropertyValue "Google Places API, fetched $(Get-Date -Format 'yyyy-MM-dd')" -Force
    $json = $d | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($file, $json, [System.Text.UTF8Encoding]::new($false))
    $namesJoined = (@($restaurants | ForEach-Object { $_.name })) -join ', '
    Write-Host "  Saved $($restaurants.Count) restaurants: $namesJoined" -ForegroundColor Green
}
Write-Host ''
Write-Host 'Done. Restaurants sourced live from Google Places.' -ForegroundColor DarkGray

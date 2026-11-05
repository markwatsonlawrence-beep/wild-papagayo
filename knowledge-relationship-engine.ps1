param(
    [Parameter(Mandatory)]
    [ValidateSet("hotel","tour","destination")]
    [string]$EntityType,

    [Parameter(Mandatory)]
    [string]$EntityId
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# --- Resolve entity file (master first, fallback to legacy) ---
$masterPath = Join-Path $root "knowledge\master\${EntityType}s\$EntityId.json"
$legacyMap  = @{
    hotel       = "knowledge\hotels\$EntityId.json"
    tour        = "knowledge\tours\$EntityId.json"
    destination = "knowledge\destinations\$EntityId.json"
}
$legacyPath = Join-Path $root $legacyMap[$EntityType]

if (Test-Path $masterPath) {
    $filePath = $masterPath
} elseif (Test-Path $legacyPath) {
    $filePath = $legacyPath
} else {
    Write-Host "Entity not found: $EntityId ($EntityType)" -ForegroundColor Red
    exit 1
}

$Entity = Get-Content $filePath -Raw -Encoding UTF8 | ConvertFrom-Json

# --- Load all JSON files from a folder ---
function Get-FolderJson {
    param([string]$Path)
    $items = @()
    if (-not (Test-Path $Path)) { return $items }
    Get-ChildItem $Path -Filter "*.json" | ForEach-Object {
        try { $items += (Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
    }
    return $items
}

# --- Extract entity properties for matching ---
$pickupZone  = ""
$tierLevel = ""
$destId      = ""
$nearbyDests = @()
$entityName  = $EntityId

if ($EntityType -eq "hotel") {
    if ($Entity.location) {
        $pickupZone = [string]$Entity.location.tour_pickup_zone
        $destId     = [string]$Entity.location.destination_id
    }
    if ($Entity.identity) {
        $tierLevel = [string]$Entity.identity.luxury_level
        if ($Entity.identity.display_name)   { $entityName = [string]$Entity.identity.display_name }
        elseif ($Entity.identity.official_name) { $entityName = [string]$Entity.identity.official_name }
    }
    if ($Entity.recommendations -and $Entity.recommendations.nearby_destinations) {
        $nearbyDests = @($Entity.recommendations.nearby_destinations)
    }
} elseif ($EntityType -eq "tour") {
    if ($Entity.name) { $entityName = [string]$Entity.name }
    if ($Entity.destination_ids -and @($Entity.destination_ids).Count -gt 0) {
        $destId = [string](@($Entity.destination_ids)[0])
    }
} elseif ($EntityType -eq "destination") {
    if ($Entity.name) { $entityName = [string]$Entity.name }
    $destId = $EntityId
    if ($Entity.nearby) { $nearbyDests = @($Entity.nearby) }
}

Write-Host ""
Write-Host "Discovering relationships for: $entityName ($EntityType)" -ForegroundColor Cyan
Write-Host ""

# --- Load all tours ---
$allTours = @(Get-FolderJson (Join-Path $root "knowledge\tours"))

# --- Discover related tours ---
$relatedTourIds = @()

foreach ($tour in $allTours) {
    $tourId = [string]$tour.id
    if (-not $tourId) { continue }
    if ($tourId -eq $EntityId) { continue }

    $isMatch = $false

    if ($EntityType -eq "hotel") {
        $featHotels = @(if ($tour.featured_hotel_ids) { $tour.featured_hotel_ids } else { @() })
        if ($featHotels -contains $EntityId) { $isMatch = $true }
        if (-not $isMatch -and $pickupZone) {
            $zones = @(if ($tour.pickup_zone_ids) { $tour.pickup_zone_ids } else { @() })
            if ($zones -contains $pickupZone) { $isMatch = $true }
        }
    } elseif ($EntityType -eq "destination") {
        $tourDests = @(if ($tour.destination_ids) { $tour.destination_ids } else { @() })
        if ($tourDests -contains $destId) { $isMatch = $true }
        if (-not $isMatch -and $Entity.featured_tours) {
            $featTours = @($Entity.featured_tours)
            if ($featTours -contains $tourId) { $isMatch = $true }
        }
    }

    if ($isMatch -and $relatedTourIds -notcontains $tourId) {
        $relatedTourIds += $tourId
    }
}

# Hotels: also merge explicitly listed featured_tours
if ($EntityType -eq "hotel" -and $Entity.recommendations -and $Entity.recommendations.featured_tours) {
    foreach ($tid in @($Entity.recommendations.featured_tours)) {
        $tStr = [string]$tid
        if ($tStr -and $relatedTourIds -notcontains $tStr) { $relatedTourIds += $tStr }
    }
}

# --- Discover related destinations ---
$relatedDestIds = @()
if ($destId -and $relatedDestIds -notcontains $destId) { $relatedDestIds += $destId }
foreach ($d in $nearbyDests) {
    $dStr = [string]$d
    if ($dStr -and $relatedDestIds -notcontains $dStr) { $relatedDestIds += $dStr }
}

# --- Discover nearby hotels (hotel-to-hotel only) ---
$nearbyHotelIds = @()
if ($EntityType -eq "hotel") {
    $masterHotelsPath = Join-Path $root "knowledge\master\hotels"
    if (Test-Path $masterHotelsPath) {
        Get-ChildItem $masterHotelsPath -Filter "*.json" | ForEach-Object {
            if ($_.BaseName -eq $EntityId) { return }
            try {
                $other       = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $otherId     = [string](if ($other.identity) { $other.identity.id } else { "" })
                $otherZone   = [string](if ($other.location) { $other.location.tour_pickup_zone } else { "" })
                $otherTier = [string](if ($other.identity) { $other.identity.luxury_level } else { "" })
                $otherDest   = [string](if ($other.location) { $other.location.destination_id } else { "" })

                $isNear = ($pickupZone  -and $otherZone   -eq $pickupZone) -or
                          ($destId      -and $otherDest   -eq $destId)     -or
                          ($tierLevel -and $otherTier -eq $tierLevel)

                if ($isNear -and $otherId -and $nearbyHotelIds -notcontains $otherId) {
                    $nearbyHotelIds += $otherId
                }
            } catch {}
        }
    }
}

# --- Build relationships object ---
$Relationships = [PSCustomObject]@{
    tours          = $relatedTourIds
    destinations   = $relatedDestIds
    nearby_hotels  = $nearbyHotelIds
    blogs          = @()
    last_discovered = (Get-Date -Format "yyyy-MM-dd")
}

# --- Upsert relationships field ---
$Entity | Add-Member -NotePropertyName "relationships" -NotePropertyValue $Relationships -Force

$json = $Entity | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($filePath, $json, [System.Text.UTF8Encoding]::new($false))

# --- Report ---
Write-Host "  Tours:         $($relatedTourIds.Count)"
foreach ($t in $relatedTourIds) { Write-Host "    - $t" }
Write-Host "  Destinations:  $($relatedDestIds.Count)"
foreach ($d in $relatedDestIds) { Write-Host "    - $d" }
Write-Host "  Nearby Hotels: $($nearbyHotelIds.Count)"
foreach ($h in $nearbyHotelIds) { Write-Host "    - $h" }
Write-Host ""
Write-Host "Relationships saved." -ForegroundColor Green

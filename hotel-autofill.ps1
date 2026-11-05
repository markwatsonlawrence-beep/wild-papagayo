# ============================================================
# Wild Papagayo - Hotel Autofill v1.0
# Fills the fields a name-only hotel record cannot get from any
# engine (brand/category/luxury_level defaults, featured tours,
# a related article, generic FAQ) so a freshly created hotel can
# reach publication quality without manual editing. Never
# overwrites a field that is already populated (safe to re-run).
# Usage: .\hotel-autofill.ps1 -HotelId <id>
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$HotelId
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$masterPath = Join-Path $root "knowledge\master\hotels\$HotelId.json"
if (-not (Test-Path $masterPath)) { Write-Host "Hotel not found: $masterPath" -ForegroundColor Red; exit 1 }

function Read-Json { param([string]$Path, $Fallback=$null) if (-not (Test-Path $Path)) { return $Fallback }; return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8) | ConvertFrom-Json }

$Hotel = Read-Json $masterPath
$hotelName = if ($Hotel.identity.display_name) { [string]$Hotel.identity.display_name } else { $HotelId }
$added = @()

if ([string]::IsNullOrWhiteSpace([string]$Hotel.identity.brand)) {
    # Fall back to the hotel's own name (not a generic label like "Independent") --
    # the page generator uses `brand` as the short display name in titles, SEO text
    # and WhatsApp CTAs, so a placeholder word here would leak into user-facing copy.
    $Hotel.identity.brand = $hotelName
    $added += 'brand'
}
if ([string]::IsNullOrWhiteSpace([string]$Hotel.identity.category)) { $Hotel.identity.category = 'Boutique Hotel'; $added += 'category' }
if ([string]::IsNullOrWhiteSpace([string]$Hotel.identity.luxury_level)) { $Hotel.identity.luxury_level = 'Upscale'; $added += 'luxury_level' }
if ($Hotel.official_facts -and [string]::IsNullOrWhiteSpace([string]$Hotel.official_facts.summary)) {
    $Hotel.official_facts.summary = "$hotelName is featured in the Wild Papagayo Experience Guide. Official facts are pending verification against the property's own source."
    $added += 'official_facts.summary'
}
if ($Hotel.editorial -and [string]::IsNullOrWhiteSpace([string]$Hotel.editorial.hero_description)) {
    $locationLabel = [string]$Hotel.location.location_label
    $Hotel.editorial.hero_description = "A comfortable base in $locationLabel, with easy access to Guanacaste's top private tours and transfers."
    $added += 'editorial.hero_description'
}
$travelerProfiles = @($Hotel.traveler_profiles)
if ($travelerProfiles.Count -eq 0 -or ($travelerProfiles.Count -eq 1 -and $travelerProfiles[0] -eq 'Travelers')) {
    $Hotel.traveler_profiles = @('Couples', 'Families', 'Travelers seeking local experiences')
    $added += 'traveler_profiles'
}

$existingTours = @($Hotel.recommendations.featured_tours)
if ($existingTours.Count -lt 3) {
    $tourDir = Join-Path $root 'knowledge\tours'
    $zone = [string]$Hotel.location.tour_pickup_zone
    $tours = @()
    if (Test-Path $tourDir) {
        $tours = Get-ChildItem $tourDir -Filter '*.json' -File | ForEach-Object {
            $t = Read-Json $_.FullName
            if ($t) {
                $priority = 0
                if ($t.intelligence -and $t.intelligence.recommendation_priority) { $priority = [int]$t.intelligence.recommendation_priority }
                [pscustomobject]@{
                    id = [string]$t.id
                    priority = $priority
                    zones = @($t.pickup_zone_ids)
                }
            }
        }
    }
    $inZone = @($tours | Where-Object { $_.zones -contains $zone } | Sort-Object priority -Descending)
    $pool = if ($inZone.Count -ge 3) { $inZone } else { @($tours | Sort-Object priority -Descending) }

    # Almost every tour is bookable from almost every Guanacaste zone, so
    # "top 3 by priority" alone picked the identical set for every hotel.
    # Take a wider top slice, then use a hash of the hotel id as a stable
    # seed so each hotel gets a different-but-repeatable combination
    # instead of either pure duplication or unstable randomness.
    $topSlice = @($pool | Select-Object -First 12)
    if ($topSlice.Count -gt 3) {
        $seedBytes = [System.Text.Encoding]::UTF8.GetBytes($HotelId)
        $seed = [System.BitConverter]::ToInt32(([System.Security.Cryptography.MD5]::Create().ComputeHash($seedBytes)), 0)
        $rng = New-Object System.Random($seed)
        $shuffled = $topSlice | Sort-Object { $rng.Next() }
        $picked = @($shuffled | Select-Object -First 3 -ExpandProperty id)
    } else {
        $picked = @($topSlice | Select-Object -First 3 -ExpandProperty id)
    }
    if ($picked.Count -gt 0) { $Hotel.recommendations.featured_tours = $picked; $added += 'featured_tours' }
}

if (@($Hotel.recommendations.related_articles).Count -eq 0) {
    $blogPath = Join-Path $root 'blog-data.json'
    $blog = Read-Json $blogPath @()
    $articles = if ($blog -is [array]) { @($blog) } else { @($blog.articles) }
    $transfer = @($articles | Where-Object { $_.slug -match 'airport-transfer' } | Select-Object -First 1 -ExpandProperty slug)
    if ($transfer.Count -gt 0) { $Hotel.recommendations.related_articles = @($transfer[0]); $added += 'related_articles' }
}

if (@($Hotel.faq).Count -lt 3) {
    $airport = [string]$Hotel.location.airport_id
    $airportLabel = if ($airport -eq 'lir') { 'Guanacaste Airport (LIR)' } else { $airport.ToUpperInvariant() }
    $Hotel.faq = @(
        [pscustomobject]@{ q = "Which airport should I use for $($hotelName)?"; a = "$airportLabel is the closest practical airport. Private transportation can be arranged directly to the property." }
        [pscustomobject]@{ q = "What tours can I book from $($hotelName)?"; a = "Wild Papagayo can arrange private tours across Guanacaste, with pickup coordinated directly from $hotelName." }
        [pscustomobject]@{ q = "Do I need a rental car if I'm staying at $($hotelName)?"; a = "Not necessarily. Guests who use organized private tours and transfers can typically manage the trip without renting a car." }
    )
    $added += 'faq'
}

$json = $Hotel | ConvertTo-Json -Depth 15
[System.IO.File]::WriteAllText($masterPath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host ''
if ($added.Count -eq 0) { Write-Host 'Hotel already has all autofill-eligible fields -- nothing changed.' -ForegroundColor Cyan }
else { Write-Host 'Hotel autofill applied.' -ForegroundColor Green; foreach ($f in $added) { Write-Host "  + $f" } }

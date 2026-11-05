param(
    [int]$Top = 50,
    [switch]$OpenReport
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$hotelDir = Join-Path $root "knowledge\master\hotels"
$tourDir = Join-Path $root "knowledge\tours"
$destinationDir = Join-Path $root "knowledge\destinations"
$blogDataPath = Join-Path $root "blog-data.json"
$outDir = Join-Path $root "knowledge\content\opportunities"
$reportDir = Join-Path $root "reports\content"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }

    return (
        [System.IO.File]::ReadAllText(
            $Path,
            [System.Text.Encoding]::UTF8
        ) | ConvertFrom-Json
    )
}

function Get-PropertyValue {
    param($Object, [string]$Name, $Default = $null)

    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function ConvertTo-Slug {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }

    $normalized = $Value.ToLowerInvariant().Normalize(
        [System.Text.NormalizationForm]::FormD
    )

    $builder = New-Object System.Text.StringBuilder

    foreach ($character in $normalized.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($character)

        if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }

    return (
        $builder.ToString().
        Normalize([System.Text.NormalizationForm]::FormC) `
        -replace '[^a-z0-9]+', '-' `
        -replace '(^-|-$)', ''
    )
}

function Add-Opportunity {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Type,
        [string]$Title,
        [string]$PrimaryEntityType,
        [string]$PrimaryEntityId,
        [string[]]$RelatedIds,
        [int]$Priority,
        [string]$SearchIntent,
        [string]$Reason
    )

    $slug = ConvertTo-Slug $Title

    $List.Add([pscustomobject][ordered]@{
        id = "$Type-$slug"
        type = $Type
        title = $Title
        slug = $slug
        primary_entity_type = $PrimaryEntityType
        primary_entity_id = $PrimaryEntityId
        related_ids = @($RelatedIds | Where-Object { $_ } | Select-Object -Unique)
        priority = $Priority
        search_intent = $SearchIntent
        reason = $Reason
        status = "suggested"
    })
}

$articles = @()
if (Test-Path $blogDataPath) {
    $articles = @(Read-JsonFile $blogDataPath)
}

$existingSlugs = @{}
foreach ($article in $articles) {
    $slug = [string](Get-PropertyValue $article "slug" "")
    if (-not [string]::IsNullOrWhiteSpace($slug)) {
        $existingSlugs[$slug] = $true
    }
}

$hotels = @()
if (Test-Path $hotelDir) {
    foreach ($file in Get-ChildItem $hotelDir -Filter "*.json" -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' }) {
        $hotel = Read-JsonFile $file.FullName
        if ($hotel) { $hotels += $hotel }
    }
}

$tours = @()
if (Test-Path $tourDir) {
    foreach ($file in Get-ChildItem $tourDir -Filter "*.json" -File) {
        $tour = Read-JsonFile $file.FullName
        if ($tour) { $tours += $tour }
    }
}

$destinations = @()
if (Test-Path $destinationDir) {
    foreach ($file in Get-ChildItem $destinationDir -Filter "*.json" -File) {
        $destination = Read-JsonFile $file.FullName
        if ($destination) { $destinations += $destination }
    }
}

$opportunities = New-Object 'System.Collections.Generic.List[object]'

# Hotel-driven opportunities
foreach ($hotel in $hotels) {
    $identity = Get-PropertyValue $hotel "identity" $null
    $location = Get-PropertyValue $hotel "location" $null
    $recommendations = Get-PropertyValue $hotel "recommendations" $null

    $hotelId = [string](Get-PropertyValue $identity "id" "")
    $hotelName = [string](Get-PropertyValue $identity "display_name" (Get-PropertyValue $identity "official_name" $hotelId))
    $destinationId = [string](Get-PropertyValue $location "destination_id" "")
    $tourIds = @((Get-PropertyValue $recommendations "featured_tours" @()))

    Add-Opportunity $opportunities "hotel-tours" `
        "Best Tours From $hotelName" "hotel" $hotelId $tourIds 98 `
        "commercial investigation" `
        "Connects a high-intent hotel stay with bookable Wild Papagayo experiences."

    Add-Opportunity $opportunities "hotel-itinerary" `
        "A Balanced 7-Day Stay at $hotelName" "hotel" $hotelId $tourIds 94 `
        "trip planning" `
        "Helps guests distribute resort time, excursions and transfers across a typical stay."

    Add-Opportunity $opportunities "hotel-transfer" `
        "Guanacaste Airport to ${hotelName}: Transfer Guide" "hotel" $hotelId @($destinationId) 92 `
        "transactional" `
        "Targets travelers who already selected the hotel and need transportation."

    Add-Opportunity $opportunities "hotel-guide" `
        "Is $hotelName Right for Your Costa Rica Trip?" "hotel" $hotelId @($destinationId) 88 `
        "comparison and decision" `
        "Uses the Experience Guide to help travelers decide whether the property matches their trip style."
}

# Destination-driven opportunities
foreach ($destination in $destinations) {
    $destinationId = [string](Get-PropertyValue $destination "id" "")
    $destinationName = [string](Get-PropertyValue $destination "name" $destinationId)

    if ([string]::IsNullOrWhiteSpace($destinationId)) { continue }

    $relatedTourIds = @(
        $tours | Where-Object {
            @((Get-PropertyValue $_ "destination_ids" @())) -contains $destinationId
        } | ForEach-Object {
            [string](Get-PropertyValue $_ "id" "")
        }
    )

    Add-Opportunity $opportunities "destination-things-to-do" `
        "Best Things to Do in $destinationName" "destination" $destinationId $relatedTourIds 90 `
        "informational and commercial" `
        "Creates a destination hub connected to tours and Experience Guides."

    Add-Opportunity $opportunities "destination-itinerary" `
        "How to Spend 7 Days Around $destinationName" "destination" $destinationId $relatedTourIds 84 `
        "trip planning" `
        "Builds a useful stay plan using the destination and tour knowledge graph."
}

# Tour-driven opportunities
foreach ($tour in $tours) {
    $tourId = [string](Get-PropertyValue $tour "id" "")
    $tourName = [string](Get-PropertyValue $tour "name" $tourId)
    $destinationIds = @((Get-PropertyValue $tour "destination_ids" @()))
    $activityIds = @((Get-PropertyValue $tour "activity_ids" @()))

    if ([string]::IsNullOrWhiteSpace($tourId)) { continue }

    Add-Opportunity $opportunities "tour-guide" `
        "Is $tourName Worth It?" "tour" $tourId @($destinationIds + $activityIds) 80 `
        "decision support" `
        "Answers a direct traveler question and links the tour to relevant destinations."

    Add-Opportunity $opportunities "tour-planning" `
        "What to Know Before Booking $tourName" "tour" $tourId @($destinationIds + $activityIds) 76 `
        "pre-purchase information" `
        "Supports conversion with duration, difficulty, pickup and practical planning details."
}

# Useful comparisons based on known high-interest entities
$comparisonPairs = @(
    @("celesteriver", "buenavistamegacombo", "Río Celeste vs Buena Vista: Which Experience Is Better?"),
    @("hangingbridgessloths", "paloverderiverboattour", "Hanging Bridges and Sloths vs Palo Verde Boat Tour"),
    @("andaz-costa-rica", "four-seasons-papagayo", "Andaz vs Four Seasons Papagayo: Which Stay Fits You?")
)

foreach ($pair in $comparisonPairs) {
    Add-Opportunity $opportunities "comparison" $pair[2] "comparison" $pair[0] @($pair[0], $pair[1]) 93 `
        "comparison" `
        "Comparison pages help travelers choose between two realistic alternatives."
}

# Remove opportunities that already exist as articles and deduplicate by slug
$filtered = @(
    $opportunities |
    Where-Object { -not $existingSlugs.ContainsKey($_.slug) } |
    Group-Object slug |
    ForEach-Object {
        $_.Group | Sort-Object priority -Descending | Select-Object -First 1
    } |
    Sort-Object @{ Expression = "priority"; Descending = $true }, @{ Expression = "title"; Descending = $false } |
    Select-Object -First $Top
)

$output = [pscustomobject][ordered]@{
    schema_version = "1.0"
    generated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    knowledge_summary = [pscustomobject][ordered]@{
        hotels = $hotels.Count
        tours = $tours.Count
        destinations = $destinations.Count
        existing_articles = $articles.Count
    }
    total_opportunities = $filtered.Count
    opportunities = $filtered
}

$jsonPath = Join-Path $outDir "content-opportunities.json"
$json = $output | ConvertTo-Json -Depth 15
[System.IO.File]::WriteAllText(
    $jsonPath,
    $json,
    (New-Object System.Text.UTF8Encoding($false))
)

$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add("WILD CONTENT OPPORTUNITY REPORT")
$lines.Add("Generated: $($output.generated)")
$lines.Add("")
$lines.Add("Hotels: $($hotels.Count) | Tours: $($tours.Count) | Destinations: $($destinations.Count) | Existing articles: $($articles.Count)")
$lines.Add("Opportunities: $($filtered.Count)")
$lines.Add("")

$position = 1
foreach ($item in $filtered) {
    $lines.Add(("{0,2}. [{1}] {2}" -f $position, $item.priority, $item.title))
    $lines.Add("    ID: $($item.id)")
    $lines.Add("    Intent: $($item.search_intent)")
    $lines.Add("    Why: $($item.reason)")
    $lines.Add("")
    $position++
}

$txtPath = Join-Path $reportDir "content-opportunities.txt"
[System.IO.File]::WriteAllLines(
    $txtPath,
    $lines,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ""
Write-Host "Content Opportunity Engine complete." -ForegroundColor Cyan
Write-Host "Hotels: $($hotels.Count) | Tours: $($tours.Count) | Destinations: $($destinations.Count) | Articles: $($articles.Count)"
Write-Host "Opportunities: $($filtered.Count)"
Write-Host "JSON: $jsonPath"
Write-Host "Report: $txtPath"
Write-Host ""

foreach ($item in ($filtered | Select-Object -First 10)) {
    Write-Host ("  {0,3}  {1}" -f $item.priority, $item.title) -ForegroundColor Green
}

if ($OpenReport) {
    Start-Process $txtPath
}

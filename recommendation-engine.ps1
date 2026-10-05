# ============================================================
# Wild Papagayo - Recommendation Engine v1.0
# Builds deterministic recommendations from the Knowledge Graph.
# Compatible with Windows PowerShell 5.1.
# Usage: .\recommendation-engine.ps1
# ============================================================

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$knowledgeDir = Join-Path $root "knowledge"
$reportsDir = Join-Path $root "reports"
$rulesPath = Join-Path $knowledgeDir "recommendation-rules.json"
$toursDir = Join-Path $knowledgeDir "tours"
$pricingJsonPath = Join-Path $root "tour-pricing.json"
$hotelsDir = Join-Path $knowledgeDir "hotels"
$destinationsDir = Join-Path $knowledgeDir "destinations"
$blogPath = Join-Path $root "blog-data.json"
$outputPath = Join-Path $knowledgeDir "recommendations.json"
$reportPath = Join-Path $reportsDir "recommendation-report.txt"
$htmlReportPath = Join-Path $reportsDir "recommendation-report.html"

New-Item -ItemType Directory -Force $reportsDir | Out-Null

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Missing required file: $Path" }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Get-NormalizedArray {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    $result = @()
    foreach ($item in @($Value)) {
        if ($null -ne $item) {
            $text = $item.ToString().Trim().ToLowerInvariant()
            if ($text.Length -gt 0) { $result += $text }
        }
    }
    return @($result | Select-Object -Unique)
}

function Test-AnyShared {
    param([object]$Left, [object]$Right)
    $a = Get-NormalizedArray $Left
    $b = Get-NormalizedArray $Right
    foreach ($item in $a) {
        if ($b -contains $item) { return $true }
    }
    return $false
}

function Get-SharedValues {
    param([object]$Left, [object]$Right)
    $a = Get-NormalizedArray $Left
    $b = Get-NormalizedArray $Right
    $shared = @()
    foreach ($item in $a) {
        if ($b -contains $item) { $shared += $item }
    }
    return @($shared | Select-Object -Unique)
}

function Add-Reason {
    param([array]$Reasons, [string]$Reason)
    if ([string]::IsNullOrWhiteSpace($Reason)) { return @($Reasons) }
    if (@($Reasons) -notcontains $Reason) { return @($Reasons) + $Reason }
    return @($Reasons)
}

function Get-ObjectProperty {
    param([object]$Object, [string]$Name, [object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function ConvertTo-HtmlSafe {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Value.ToString())
}

function Get-CanonicalTourFromPrice {
    # Same "public starting price" contract tour-generator.ps1's teaser and
    # tours-catalog-pricing-sync.ps1's catalog cards already use: the
    # minimum pp_2/pp_3/pp_4plus across every ACTIVE option for this tour in
    # tour-pricing.json. Returns $null (never 0) when the tour has no
    # tour-pricing.json entry, no ACTIVE option, or is MANUAL QUOTE only --
    # recommendations must show the same "no starting price" state the
    # public page shows, never a guessed number.
    param([object]$PricingData, [string]$TourId)
    if ($null -eq $PricingData) { return $null }
    $entry = Get-ObjectProperty $PricingData.tours $TourId $null
    if ($null -eq $entry) { return $null }
    $activeOpts = @(Get-ObjectProperty $entry 'options' @() | Where-Object { (Get-ObjectProperty $_ 'estimator_status' '') -eq 'active' })
    if ($activeOpts.Count -eq 0) { return $null }
    $minVal = $null
    foreach ($opt in $activeOpts) {
        foreach ($tierField in @('pp_2', 'pp_3', 'pp_4plus')) {
            $tierVal = Get-ObjectProperty $opt $tierField $null
            if ($null -ne $tierVal -and ($null -eq $minVal -or [double]$tierVal -lt $minVal)) { $minVal = [double]$tierVal }
        }
    }
    return $minVal
}

$errors = @()
$warnings = @()

try { $rules = Read-JsonFile $rulesPath } catch { $errors += $_.Exception.Message; $rules = $null }
try { $tourPricingData = Read-JsonFile $pricingJsonPath } catch { $errors += $_.Exception.Message; $tourPricingData = $null }

$tours = @()
if (Test-Path $toursDir) {
    foreach ($file in @(Get-ChildItem -Path $toursDir -Filter "*.json" -File | Sort-Object Name)) {
        try { $tours += Read-JsonFile $file.FullName } catch { $errors += "$($file.Name): $($_.Exception.Message)" }
    }
} else { $errors += "Missing tours directory: knowledge/tours" }

$hotels = @()
if (Test-Path $hotelsDir) {
    foreach ($file in @(Get-ChildItem -Path $hotelsDir -Filter "*.json" -File | Sort-Object Name)) {
        try { $hotels += Read-JsonFile $file.FullName } catch { $errors += "$($file.Name): $($_.Exception.Message)" }
    }
} else { $warnings += "Hotels directory is missing; hotel recommendations were skipped." }

$destinations = @()
if (Test-Path $destinationsDir) {
    foreach ($file in @(Get-ChildItem -Path $destinationsDir -Filter "*.json" -File | Sort-Object Name)) {
        try { $destinations += Read-JsonFile $file.FullName } catch { $errors += "$($file.Name): $($_.Exception.Message)" }
    }
} else { $errors += "Missing destinations directory: knowledge/destinations" }

$blogs = @()
if (Test-Path $blogPath) {
    try { $blogsRaw = [System.IO.File]::ReadAllText($blogPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json; $blogs = @($blogsRaw) } catch { $errors += $_.Exception.Message }
} else { $warnings += "blog-data.json is missing; blog recommendations were skipped." }

if ($null -eq $rules) { $errors += "Recommendation rules could not be loaded." }

$tourById = @{}
foreach ($tour in $tours) {
    $id = [string](Get-ObjectProperty $tour "id" "")
    if ([string]::IsNullOrWhiteSpace($id)) { $errors += "A tour is missing its id."; continue }
    if ($tourById.ContainsKey($id)) { $errors += "Duplicate tour id: $id" } else { $tourById[$id] = $tour }
}

$destinationById = @{}
foreach ($destination in $destinations) {
    $id = [string](Get-ObjectProperty $destination "id" "")
    if ([string]::IsNullOrWhiteSpace($id)) { $errors += "A destination is missing its id."; continue }
    if ($destinationById.ContainsKey($id)) { $errors += "Duplicate destination id: $id" } else { $destinationById[$id] = $destination }
}

$hotelById = @{}
foreach ($hotel in $hotels) {
    $id = [string](Get-ObjectProperty $hotel "id" "")
    if ([string]::IsNullOrWhiteSpace($id)) { $errors += "A hotel is missing its id."; continue }
    if ($hotelById.ContainsKey($id)) { $errors += "Duplicate hotel id: $id" } else { $hotelById[$id] = $hotel }
}

if ($errors.Count -gt 0) {
    $lines = @("Wild Engine - Recommendation Report", "Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))", "Errors: $($errors.Count)", "Warnings: $($warnings.Count)", "", "ERRORS") + @($errors | ForEach-Object { "- $_" })
    [System.IO.File]::WriteAllLines($reportPath, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Recommendation Engine validation failed." -ForegroundColor Red
    Write-Host "Errors: $($errors.Count) | Warnings: $($warnings.Count)" -ForegroundColor Red
    Write-Host "Report: reports/recommendation-report.txt"
    exit 1
}

$w = $rules.weights
$limits = $rules.limits
$minimum = $rules.minimum_scores

function New-RecommendationItem {
    param([object]$Tour, [int]$Score, [array]$Reasons)
    return [pscustomobject][ordered]@{
        id = [string]$Tour.id
        name = [string]$Tour.name
        score = $Score
        reasons = @($Reasons)
        category = [string](Get-ObjectProperty $Tour "category" "")
        url = [string](Get-ObjectProperty $Tour "page_url" "")
        image = [string](Get-ObjectProperty $Tour "hero_image" "")
        duration = [string](Get-ObjectProperty $Tour "duration_label" "")
        from_price = Get-CanonicalTourFromPrice -PricingData $tourPricingData -TourId ([string]$Tour.id)
        currency = "USD"
    }
}

function Select-TopRecommendations {
    param([array]$Items, [int]$Limit, [int]$MinimumScore)
    return @($Items | Where-Object { $_.score -ge $MinimumScore } | Sort-Object @{Expression="score";Descending=$true}, @{Expression="name";Descending=$false} | Select-Object -First $Limit)
}

$hotelRecommendations = [ordered]@{}
foreach ($hotel in $hotels) {
    $items = @()
    $hotelFeaturedTours = Get-NormalizedArray (Get-ObjectProperty $hotel "featured_tours" @())
    $hotelNearbyDestinations = Get-NormalizedArray (Get-ObjectProperty $hotel "nearby_destinations" @())
    $hotelDestination = ([string](Get-ObjectProperty $hotel "destination_id" "")).ToLowerInvariant()
    $hotelPickupZone = ([string](Get-ObjectProperty $hotel "tour_pickup_zone" "")).ToLowerInvariant()

    foreach ($tour in $tours) {
        if ([string](Get-ObjectProperty $tour "status" "active") -ne "active") { continue }
        $score = 0
        $reasons = @()
        $tourId = ([string]$tour.id).ToLowerInvariant()
        $tourHotels = Get-NormalizedArray (Get-ObjectProperty $tour "featured_hotel_ids" @())
        $tourDestinations = Get-NormalizedArray (Get-ObjectProperty $tour "destination_ids" @())
        $tourPickupZones = Get-NormalizedArray (Get-ObjectProperty $tour "pickup_zone_ids" @())

        if ($hotelFeaturedTours -contains $tourId) { $score += [int]$w.explicit_hotel_featured_tour; $reasons = Add-Reason $reasons "Featured by this hotel profile" }
        if ($tourHotels -contains ([string]$hotel.id).ToLowerInvariant()) { $score += [int]$w.tour_featured_hotel; $reasons = Add-Reason $reasons "Tour profile features this hotel" }
        if ($hotelPickupZone.Length -gt 0 -and $tourPickupZones -contains $hotelPickupZone) { $score += [int]$w.shared_pickup_zone; $reasons = Add-Reason $reasons "Available from the same pickup zone" }
        if ($hotelDestination.Length -gt 0 -and $tourDestinations -contains $hotelDestination) { $score += [int]$w.hotel_destination_match; $reasons = Add-Reason $reasons "Matches the hotel destination" }
        if (Test-AnyShared $hotelNearbyDestinations $tourDestinations) { $score += [int]$w.hotel_nearby_destination_match; $reasons = Add-Reason $reasons "Matches a nearby destination" }
        $score += [int]$w.active_tour_bonus
        $price = Get-CanonicalTourFromPrice -PricingData $tourPricingData -TourId ([string]$tour.id)
        if ($null -ne $price) { $score += [int]$w.priced_tour_bonus }

        if ($score -gt 0) { $items += New-RecommendationItem $tour $score $reasons }
    }
    $hotelRecommendations[[string]$hotel.id] = @(Select-TopRecommendations $items ([int]$limits.hotel_tours) ([int]$minimum.hotel_tours))
}

$destinationRecommendations = [ordered]@{}
foreach ($destination in $destinations) {
    $items = @()
    $destinationId = ([string]$destination.id).ToLowerInvariant()
    $featuredTours = Get-NormalizedArray (Get-ObjectProperty $destination "featured_tours" @())
    $nearbyDestinations = Get-NormalizedArray (Get-ObjectProperty $destination "nearby" @())

    foreach ($tour in $tours) {
        if ([string](Get-ObjectProperty $tour "status" "active") -ne "active") { continue }
        $score = 0
        $reasons = @()
        $tourId = ([string]$tour.id).ToLowerInvariant()
        $tourDestinations = Get-NormalizedArray (Get-ObjectProperty $tour "destination_ids" @())
        if ($featuredTours -contains $tourId) { $score += [int]$w.destination_featured_tour; $reasons = Add-Reason $reasons "Featured by this destination" }
        if ($tourDestinations -contains $destinationId) { $score += [int]$w.tour_destination_match; $reasons = Add-Reason $reasons "Tour takes place in this destination" }
        if (Test-AnyShared $nearbyDestinations $tourDestinations) { $score += [int]$w.tour_nearby_destination_match; $reasons = Add-Reason $reasons "Tour takes place near this destination" }
        $score += [int]$w.active_tour_bonus
        $price = Get-CanonicalTourFromPrice -PricingData $tourPricingData -TourId ([string]$tour.id)
        if ($null -ne $price) { $score += [int]$w.priced_tour_bonus }
        if ($score -gt 0) { $items += New-RecommendationItem $tour $score $reasons }
    }
    $destinationRecommendations[[string]$destination.id] = @(Select-TopRecommendations $items ([int]$limits.destination_tours) ([int]$minimum.destination_tours))
}

$blogRecommendations = [ordered]@{}
foreach ($blog in $blogs) {
    $items = @()
    $blogDestinations = Get-NormalizedArray (Get-ObjectProperty $blog "destinations" @())
    $blogTours = Get-NormalizedArray (Get-ObjectProperty $blog "tours" @())
    $blogTags = Get-NormalizedArray (Get-ObjectProperty $blog "related_tags" @())

    foreach ($tour in $tours) {
        if ([string](Get-ObjectProperty $tour "status" "active") -ne "active") { continue }
        $score = 0
        $reasons = @()
        $tourId = ([string]$tour.id).ToLowerInvariant()
        $tourDestinations = Get-NormalizedArray (Get-ObjectProperty $tour "destination_ids" @())
        $tourActivities = Get-NormalizedArray (Get-ObjectProperty $tour "activity_ids" @())
        if ($blogTours -contains $tourId) { $score += [int]$w.blog_explicit_tour; $reasons = Add-Reason $reasons "Explicitly linked to this article" }
        if (Test-AnyShared $blogDestinations $tourDestinations) { $score += [int]$w.blog_destination_match; $reasons = Add-Reason $reasons "Matches an article destination" }
        $tagActivityMatches = Get-SharedValues $blogTags $tourActivities
        if ($tagActivityMatches.Count -gt 0) { $score += ([int]$w.blog_tag_activity_match * $tagActivityMatches.Count); $reasons = Add-Reason $reasons "Matches article interests" }
        if ($score -gt 0) {
            $score += [int]$w.active_tour_bonus
            $items += New-RecommendationItem $tour $score $reasons
        }
    }
    $blogRecommendations[[string]$blog.slug] = @(Select-TopRecommendations $items ([int]$limits.blog_tours) ([int]$minimum.blog_tours))
}

$tourRecommendations = [ordered]@{}
foreach ($sourceTour in $tours) {
    $items = @()
    $sourceCategory = ([string](Get-ObjectProperty $sourceTour "category" "")).ToLowerInvariant()
    $sourceDestinations = Get-NormalizedArray (Get-ObjectProperty $sourceTour "destination_ids" @())
    $sourceActivities = Get-NormalizedArray (Get-ObjectProperty $sourceTour "activity_ids" @())
    $sourceHotels = Get-NormalizedArray (Get-ObjectProperty $sourceTour "featured_hotel_ids" @())

    foreach ($candidate in $tours) {
        if ([string]$candidate.id -eq [string]$sourceTour.id) { continue }
        if ([string](Get-ObjectProperty $candidate "status" "active") -ne "active") { continue }
        $score = 0
        $reasons = @()
        $candidateCategory = ([string](Get-ObjectProperty $candidate "category" "")).ToLowerInvariant()
        $candidateDestinations = Get-NormalizedArray (Get-ObjectProperty $candidate "destination_ids" @())
        $candidateActivities = Get-NormalizedArray (Get-ObjectProperty $candidate "activity_ids" @())
        $candidateHotels = Get-NormalizedArray (Get-ObjectProperty $candidate "featured_hotel_ids" @())

        if ($sourceCategory.Length -gt 0 -and $sourceCategory -eq $candidateCategory) { $score += [int]$w.same_tour_category; $reasons = Add-Reason $reasons "Same experience category" }
        if (Test-AnyShared $sourceDestinations $candidateDestinations) { $score += [int]$w.shared_tour_destination; $reasons = Add-Reason $reasons "Shared destination" }
        $sharedActivities = Get-SharedValues $sourceActivities $candidateActivities
        if ($sharedActivities.Count -gt 0) { $score += ([int]$w.shared_tour_activity * $sharedActivities.Count); $reasons = Add-Reason $reasons "Shared activities" }
        if (Test-AnyShared $sourceHotels $candidateHotels) { $score += [int]$w.shared_featured_hotel; $reasons = Add-Reason $reasons "Popular with similar hotel guests" }
        if ($score -gt 0) { $items += New-RecommendationItem $candidate $score $reasons }
    }
    $tourRecommendations[[string]$sourceTour.id] = @(Select-TopRecommendations $items ([int]$limits.tour_related_tours) ([int]$minimum.tour_related_tours))
}

$result = [ordered]@{
    version = "1.0"
    generated_at = (Get-Date).ToString("o")
    rules_file = "knowledge/recommendation-rules.json"
    counts = [ordered]@{
        hotels = $hotels.Count
        destinations = $destinations.Count
        blogs = $blogs.Count
        tours = $tours.Count
    }
    hotel_tours = $hotelRecommendations
    destination_tours = $destinationRecommendations
    blog_tours = $blogRecommendations
    tour_related_tours = $tourRecommendations
}

$json = $result | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($outputPath, $json, [System.Text.UTF8Encoding]::new($false))

$emptyHotels = @($hotelRecommendations.Keys | Where-Object { @($hotelRecommendations[$_]).Count -eq 0 })
$emptyDestinations = @($destinationRecommendations.Keys | Where-Object { @($destinationRecommendations[$_]).Count -eq 0 })
$emptyBlogs = @($blogRecommendations.Keys | Where-Object { @($blogRecommendations[$_]).Count -eq 0 })
if ($emptyHotels.Count -gt 0) { $warnings += "$($emptyHotels.Count) hotel profile(s) have no tour recommendations." }
if ($emptyDestinations.Count -gt 0) { $warnings += "$($emptyDestinations.Count) destination profile(s) have no tour recommendations." }
if ($emptyBlogs.Count -gt 0) { $warnings += "$($emptyBlogs.Count) blog article(s) have no tour recommendations." }

$report = @()
$report += "Wild Engine - Recommendation Report"
$report += "Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
$report += "Hotels: $($hotels.Count)"
$report += "Destinations: $($destinations.Count)"
$report += "Blogs: $($blogs.Count)"
$report += "Tours: $($tours.Count)"
$report += "Errors: 0"
$report += "Warnings: $($warnings.Count)"
$report += ""
$report += "RECOMMENDATION COVERAGE"
$report += "Hotel profiles with recommendations: $($hotels.Count - $emptyHotels.Count)/$($hotels.Count)"
$report += "Destination profiles with recommendations: $($destinations.Count - $emptyDestinations.Count)/$($destinations.Count)"
$report += "Blog articles with recommendations: $($blogs.Count - $emptyBlogs.Count)/$($blogs.Count)"
$report += "Tours with related tours: $(@($tourRecommendations.Keys | Where-Object { @($tourRecommendations[$_]).Count -gt 0 }).Count)/$($tours.Count)"
if ($warnings.Count -gt 0) {
    $report += ""
    $report += "WARNINGS"
    $report += @($warnings | ForEach-Object { "- $_" })
}
$report += ""
$report += "Validation passed."
[System.IO.File]::WriteAllLines($reportPath, [string[]]$report, [System.Text.UTF8Encoding]::new($false))

$hotelRows = @()
foreach ($hotel in $hotels) {
    $top = @($hotelRecommendations[[string]$hotel.id])
    $names = if ($top.Count -gt 0) { ($top | ForEach-Object { "$(ConvertTo-HtmlSafe $_.name) ($($_.score))" }) -join "<br>" } else { "No recommendations" }
    $hotelRows += "<tr><td>$(ConvertTo-HtmlSafe $hotel.name)</td><td>$($top.Count)</td><td>$names</td></tr>"
}
$destinationRows = @()
foreach ($destination in $destinations) {
    $top = @($destinationRecommendations[[string]$destination.id])
    $names = if ($top.Count -gt 0) { ($top | ForEach-Object { "$(ConvertTo-HtmlSafe $_.name) ($($_.score))" }) -join "<br>" } else { "No recommendations" }
    $destinationRows += "<tr><td>$(ConvertTo-HtmlSafe $destination.name)</td><td>$($top.Count)</td><td>$names</td></tr>"
}
$html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Wild Engine Recommendation Report</title><style>body{font-family:Arial,sans-serif;background:#f5f7fa;color:#172033;margin:0;padding:32px}.wrap{max-width:1100px;margin:auto}.card{background:#fff;border:1px solid #dfe5ec;border-radius:10px;padding:24px;margin-bottom:24px}h1,h2{color:#062448}table{width:100%;border-collapse:collapse}th,td{text-align:left;vertical-align:top;padding:12px;border-bottom:1px solid #e7ebf0}th{background:#f2f5f8}.ok{color:#087f5b;font-weight:700}.warn{color:#9a6700;font-weight:700}</style></head><body><div class="wrap"><div class="card"><h1>Wild Engine Recommendation Report</h1><p class="ok">Validation passed</p><p>Generated: $(ConvertTo-HtmlSafe ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))</p><p>Hotels: $($hotels.Count) &middot; Destinations: $($destinations.Count) &middot; Blogs: $($blogs.Count) &middot; Tours: $($tours.Count)</p><p class="$(if($warnings.Count -gt 0){'warn'}else{'ok'})">Warnings: $($warnings.Count) &middot; Errors: 0</p></div><div class="card"><h2>Hotel recommendations</h2><table><thead><tr><th>Hotel</th><th>Count</th><th>Recommended tours and score</th></tr></thead><tbody>$($hotelRows -join "`n")</tbody></table></div><div class="card"><h2>Destination recommendations</h2><table><thead><tr><th>Destination</th><th>Count</th><th>Recommended tours and score</th></tr></thead><tbody>$($destinationRows -join "`n")</tbody></table></div></div></body></html>
"@
[System.IO.File]::WriteAllText($htmlReportPath, $html, [System.Text.UTF8Encoding]::new($false))

Write-Host "Recommendation Engine completed." -ForegroundColor Green
Write-Host "Hotels: $($hotels.Count) | Destinations: $($destinations.Count) | Blogs: $($blogs.Count) | Tours: $($tours.Count)"
Write-Host "Warnings: $($warnings.Count)"
Write-Host "Output: knowledge/recommendations.json"
Write-Host "Report: reports/recommendation-report.txt"
exit 0

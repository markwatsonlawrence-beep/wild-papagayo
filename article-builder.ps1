param(
    [string]$OpportunityId,
    [string]$Title,
    [ValidateSet("hotel-tours","hotel-itinerary","hotel-transfer","hotel-guide","destination-things-to-do","destination-itinerary","tour-guide","tour-planning","comparison","custom")]
    [string]$Type = "custom",
    [string]$PrimaryEntityId,
    [switch]$PublishDraft,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$blogDataPath = Join-Path $root "blog-data.json"
$opportunitiesPath = Join-Path $root "knowledge\content\opportunities\content-opportunities.json"
$draftDir = Join-Path $root "knowledge\content\drafts"
$backupDir = Join-Path $root "knowledge\backups\blog-data"

New-Item -ItemType Directory -Force -Path $draftDir | Out-Null
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

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

function ConvertTo-HtmlSafe {
    param([string]$Value)

    if ($null -eq $Value) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Value)
}

function Get-EntityContext {
    param([string]$EntityId)

    if ([string]::IsNullOrWhiteSpace($EntityId)) { return $null }

    $paths = @(
        (Join-Path $root "knowledge\master\hotels\$EntityId.json"),
        (Join-Path $root "knowledge\tours\$EntityId.json"),
        (Join-Path $root "knowledge\destinations\$EntityId.json")
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            return Read-JsonFile $path
        }
    }

    return $null
}

$opportunity = $null

if (-not [string]::IsNullOrWhiteSpace($OpportunityId)) {
    $opportunityData = Read-JsonFile $opportunitiesPath

    if ($null -eq $opportunityData) {
        throw "Opportunity file not found. Run .\content-opportunity-engine.ps1 first."
    }

    $opportunity = @($opportunityData.opportunities) |
        Where-Object { $_.id -eq $OpportunityId } |
        Select-Object -First 1

    if ($null -eq $opportunity) {
        throw "Opportunity not found: $OpportunityId"
    }

    $Title = [string]$opportunity.title
    $Type = [string]$opportunity.type
    $PrimaryEntityId = [string]$opportunity.primary_entity_id
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    throw "Use -OpportunityId or provide -Title."
}

$slug = ConvertTo-Slug $Title
$context = Get-EntityContext $PrimaryEntityId
$articles = @()

if (Test-Path $blogDataPath) {
    $articles = @(Read-JsonFile $blogDataPath)
}

if (@($articles | Where-Object { $_.slug -eq $slug }).Count -gt 0 -and -not $Force) {
    throw "Article slug already exists: $slug. Use -Force only when intentionally replacing it."
}

$nextId = 1
if ($articles.Count -gt 0) {
    $maxId = ($articles | Measure-Object -Property id -Maximum).Maximum
    $nextId = [int]$maxId + 1
}

$today = Get-Date
$displayDate = $today.ToString("MMMM d, yyyy", [Globalization.CultureInfo]::InvariantCulture)
$isoDate = $today.ToString("yyyy-MM-ddT00:00:00Z")

$entityName = $PrimaryEntityId
$destinationIds = @()
$tourIds = @()
$hotelIds = @()
$bestFor = @("First-time visitors", "Travel planners")

if ($context) {
    $identity = Get-PropertyValue $context "identity" $null

    if ($identity) {
        $entityName = [string](Get-PropertyValue $identity "display_name" (Get-PropertyValue $identity "official_name" $PrimaryEntityId))
        $hotelIds = @($PrimaryEntityId)

        $location = Get-PropertyValue $context "location" $null
        $destinationId = [string](Get-PropertyValue $location "destination_id" "")
        if ($destinationId) { $destinationIds = @($destinationId) }

        $recommendations = Get-PropertyValue $context "recommendations" $null
        $tourIds = @((Get-PropertyValue $recommendations "featured_tours" @()))
        $bestFor = @((Get-PropertyValue $context "traveler_profiles" $bestFor))
    }
    elseif (Get-PropertyValue $context "duration_label" $null) {
        $entityName = [string](Get-PropertyValue $context "name" $PrimaryEntityId)
        $tourIds = @($PrimaryEntityId)
        $destinationIds = @((Get-PropertyValue $context "destination_ids" @()))
        $bestFor = @((Get-PropertyValue $context "best_for" $bestFor))
    }
    else {
        $entityName = [string](Get-PropertyValue $context "name" $PrimaryEntityId)
        $destinationIds = @($PrimaryEntityId)
    }
}

$excerpt = "A practical Wild Papagayo guide to $Title, built from local planning knowledge, verified entity data and bookable experiences."
$seoTitle = "$Title | Wild Papagayo"
if ($seoTitle.Length -gt 60) {
    $seoTitle = $seoTitle.Substring(0, 57).TrimEnd() + "..."
}

$seoDescription = "Plan $Title with local Guanacaste insight, practical logistics, recommended experiences and Wild Papagayo travel guidance."
if ($seoDescription.Length -gt 155) {
    $seoDescription = $seoDescription.Substring(0, 152).TrimEnd() + "..."
}

$internalLinks = @()

foreach ($tourId in $tourIds | Select-Object -First 5) {
    $tour = Get-EntityContext $tourId
    if ($tour) {
        $tourName = [string](Get-PropertyValue $tour "name" $tourId)
        $internalLinks += [pscustomobject]@{
            text = $tourName
            url = "../tours/$tourId.html"
        }
    }
}

foreach ($hotelId in $hotelIds | Select-Object -First 2) {
    $internalLinks += [pscustomobject]@{
        text = "$entityName Experience Guide"
        url = "../hotels/$hotelId.html"
    }
}

foreach ($destinationId in $destinationIds | Select-Object -First 3) {
    $internalLinks += [pscustomobject]@{
        text = "Explore $destinationId"
        url = "../destinations/$destinationId.html"
    }
}

$content1 = @"
<h2>Start With the Traveler's Main Question</h2>
<p><strong>Editorial draft:</strong> Explain why this topic matters, who it is for and the most useful answer a traveler should understand before making a decision.</p>
<h2>What Wild Papagayo Recommends</h2>
<p>Use verified facts from the linked hotel, tour or destination records. Add local operational insight, realistic transfer considerations and a balanced recommendation rather than promotional filler.</p>
"@

$content2 = @"
<h2>How to Plan It Well</h2>
<p>Cover timing, duration, transportation, pacing and how this choice fits into a typical Guanacaste stay. Avoid invented prices, schedules or inclusions.</p>
<blockquote><strong>Local Expert Tip</strong><br>Replace this placeholder with one specific, useful recommendation from Wild Papagayo's real operating experience.</blockquote>
"@

$content3 = @"
<h2>Our Bottom Line</h2>
<p>Summarize who should choose this option, who may prefer an alternative and the next practical step for planning or booking.</p>
"@

$faqHtml = @"
<h2>Frequently Asked Questions</h2>
<h3>Who is this guide best for?</h3>
<p>This draft is intended for travelers comparing options and organizing a Guanacaste itinerary.</p>
<h3>What information should be verified before publication?</h3>
<p>Confirm current operating details, travel times, pricing references and any hotel- or tour-specific policies.</p>
<h3>Can Wild Papagayo personalize this plan?</h3>
<p>Yes. The final call to action should invite the traveler to request a private itinerary, tour or transfer recommendation.</p>
"@

$draft = [pscustomobject][ordered]@{
    id = $nextId
    slug = $slug
    status = "draft"
    opportunity_id = $(if ($opportunity) { [string]$opportunity.id } else { "" })
    content_type = $Type
    category = $(switch -Regex ($Type) {
        "transfer" { "Trip Planning & Transportation"; break }
        "itinerary" { "Itineraries & Trip Planning"; break }
        "comparison" { "Travel Comparisons"; break }
        "tour" { "Tours & Experiences"; break }
        default { "Destination Guides" }
    })
    date = $displayDate
    readTime = "7"
    iso_date = $isoDate
    title = $Title
    excerpt = $excerpt
    seo_title_pro = $seoTitle
    seo_description = $seoDescription
    seo_keywords = (($Title.ToLowerInvariant() -replace '[^a-z0-9 ]', '') -split '\s+' | Where-Object { $_.Length -gt 3 } | Select-Object -Unique) -join ", "
    author_name = "Wild Papagayo Team"
    author_badge = "Costa Rica Local Experts"
    image_top = "images/luxury-costa-rica-tours-hero.webp"
    image_top_alt = "$Title in Guanacaste, Costa Rica"
    content_block_1 = $content1
    image_middle = ""
    image_middle_alt = ""
    content_block_2 = $content2
    content_block_faq = $faqHtml
    cta_url = "https://wa.me/50688566325?text=Hello%20Wild%20Papagayo!%20I%27d%20love%20help%20planning%20my%20Costa%20Rica%20trip."
    cta_text = "Plan This Experience With a Local Expert"
    image_bottom = ""
    image_bottom_alt = ""
    content_block_3 = $content3
    destination_ids = @($destinationIds)
    tour_ids = @($tourIds)
    hotel_ids = @($hotelIds)
    activity_ids = @()
    season_ids = @()
    traveler_profile_ids = @()
    related_tags = @($Type, $PrimaryEntityId) | Where-Object { $_ }
    quick_facts = @(
        "Draft generated from the Wild Papagayo knowledge repository",
        "Requires editorial and factual review before publication"
    )
    best_for = @($bestFor)
    travel_tip = "Replace this placeholder with a specific local planning recommendation."
    packing_list = @()
    did_you_know = ""
    internal_links = @($internalLinks | Select-Object -Unique text, url)
    editorial = [pscustomobject]@{
        status = "review_required"
        factual_review_required = $true
        local_insight_required = $true
        generated_from_knowledge = $true
    }
}

$draftPath = Join-Path $draftDir "$slug.json"
$draftJson = $draft | ConvertTo-Json -Depth 20

[System.IO.File]::WriteAllText(
    $draftPath,
    $draftJson,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ""
Write-Host "Article draft created." -ForegroundColor Cyan
Write-Host "Draft: $draftPath"
Write-Host "Title: $Title"
Write-Host "Slug: $slug"
Write-Host "Related tours: $($tourIds.Count)"
Write-Host "Internal links: $($internalLinks.Count)"

if ($PublishDraft) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    if (Test-Path $blogDataPath) {
        Copy-Item $blogDataPath (Join-Path $backupDir "blog-data-$stamp.json")
    }

    $newArticles = @(
        $articles | Where-Object { $_.slug -ne $slug }
    ) + @($draft)

    $blogJson = $newArticles | ConvertTo-Json -Depth 20

    [System.IO.File]::WriteAllText(
        $blogDataPath,
        $blogJson,
        (New-Object System.Text.UTF8Encoding($false))
    )

    Write-Host "Draft added to blog-data.json." -ForegroundColor Green
    Write-Host "Run .\blog-generator.ps1 after completing editorial review."
}
else {
    Write-Host "The draft was NOT added to blog-data.json." -ForegroundColor Yellow
    Write-Host "Review it first, then run again with -PublishDraft."
}

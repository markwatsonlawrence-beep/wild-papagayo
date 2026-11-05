param(
    [Parameter(Mandatory)]
    [string]$HotelId,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root     = $PSScriptRoot
$filePath = Join-Path $root "knowledge\master\hotels\$HotelId.json"

if (-not (Test-Path $filePath)) {
    Write-Host "Hotel not found: $filePath" -ForegroundColor Red
    exit 1
}

$v1 = Get-Content $filePath -Raw -Encoding UTF8 | ConvertFrom-Json

# --- Detect schema version ---
if ($v1.PSObject.Properties["identity"]) {
    Write-Host ""
    Write-Host "$HotelId is already on schema v2. No migration needed." -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "Migrating $HotelId from schema v1 to v2..." -ForegroundColor Yellow
Write-Host ""

# -----------------------------------------------------------------------
# Helper: read a root property safely
function Prop { param($Obj, $Name, $Default = $null)
    if ($Obj.PSObject.Properties[$Name]) { return $Obj.$Name }
    return $Default
}

# -----------------------------------------------------------------------
# IDENTITY block
$identity = [PSCustomObject]@{
    id            = [string](Prop $v1 "id"            $HotelId)
    official_name = [string](Prop $v1 "name"          "")
    display_name  = [string](Prop $v1 "name"          "")
    slug          = [string](Prop $v1 "slug"          $HotelId)
    brand         = [string](Prop $v1 "brand"         "")
    category      = [string](Prop $v1 "category"      "Luxury Resort")
    luxury_level  = [string](Prop $v1 "luxury_level"  "Luxury")
}

# -----------------------------------------------------------------------
# LOCATION block
$v1Transfer = Prop $v1 "transfer_minutes" $null
$transfer   = if ($v1Transfer) {
    [PSCustomObject]@{
        min         = $v1Transfer.min
        max         = $v1Transfer.max
        label       = [string](Prop $v1Transfer "label" "Transfer time from Guanacaste Airport (LIR).")
        source_type = "wild_papagayo_operational_estimate"
    }
} else { $null }

$location = [PSCustomObject]@{
    destination_id  = [string](Prop $v1 "destination_id"  "")
    location_label  = [string](Prop $v1 "location_label"  "")
    province        = [string](Prop $v1 "province"        "Guanacaste")
    airport_id      = [string](Prop $v1 "airport_id"      "lir")
    tour_pickup_zone= [string](Prop $v1 "tour_pickup_zone" "")
    transfer        = $transfer
}

# -----------------------------------------------------------------------
# OFFICIAL_SOURCES block
$sourceNotes = @(Prop $v1 "source_notes" @())
$officialUrl = [string](Prop $v1 "official_url" "")
$officialSources = @()
if ($officialUrl) {
    $officialSources += [PSCustomObject]@{
        type         = "overview"
        url          = $officialUrl
        status       = "imported"
        last_checked = (Get-Date -Format "yyyy-MM-dd")
    }
}

# -----------------------------------------------------------------------
# OFFICIAL_FACTS block
$factsNote = if ($sourceNotes.Count -gt 0) { $sourceNotes -join " " } else { "Facts imported from legacy schema." }
$officialFacts = [PSCustomObject]@{
    summary     = [string](Prop $v1 "description" "")
    features    = @()
    fact_status = "partially_verified"
    note        = $factsNote
}

# -----------------------------------------------------------------------
# EDITORIAL block
$localInsight = [string](Prop $v1 "local_insight" "")
$v1WhyStay    = Prop $v1 "why_stay_here" $null

$whyStayHere = if ($v1WhyStay) {
    $v1WhyStay
} elseif ($localInsight) {
    [PSCustomObject]@{
        title   = "Why Stay Here"
        summary = $localInsight
    }
} else {
    [PSCustomObject]@{
        title   = "Why Stay Here"
        summary = "$($identity.display_name) is an excellent base for exploring Guanacaste's nature, wildlife and adventures."
    }
}

$editorial = [PSCustomObject]@{
    hero_description = [string](Prop $v1 "hero_description" "")
    why_stay_here    = $whyStayHere
    description      = [string](Prop $v1 "description" "")
    tone             = "useful, locally informed and guest-focused"
}

# -----------------------------------------------------------------------
# EXPERIENCE_SCORES block  (renamed from hotel_scores)
$v1Scores = Prop $v1 "hotel_scores" $null
$experienceScores = if ($v1Scores) {
    # Wrap numeric scores into { score, reason } objects matching v2 schema
    $out = [PSCustomObject]@{}
    foreach ($prop in $v1Scores.PSObject.Properties) {
        $score = $prop.Value
        $out | Add-Member -NotePropertyName $prop.Name -NotePropertyValue ([PSCustomObject]@{
            score  = $score
            reason = ""
        })
    }
    $out
} else { [PSCustomObject]@{} }

# -----------------------------------------------------------------------
# RECOMMENDATIONS block
$recommendations = [PSCustomObject]@{
    featured_tours      = @(Prop $v1 "featured_tours"      @())
    related_articles    = @(Prop $v1 "related_articles"    @())
    nearby_destinations = @(Prop $v1 "nearby_destinations" @())
}

# -----------------------------------------------------------------------
# TRAVELER_PROFILES  (renamed from best_for)
$travelerProfiles = @(Prop $v1 "best_for" @())

# -----------------------------------------------------------------------
# WILD_INSIGHTS block
$wildInsights = [PSCustomObject]@{
    local_take = $localInsight
    insights   = @()
}

# -----------------------------------------------------------------------
# GALLERY block (carry over or create stub)
$v1Gallery = Prop $v1 "gallery" $null
$gallery   = if ($v1Gallery) {
    $v1Gallery
} else {
    [PSCustomObject]@{
        hero_image        = [string](Prop $v1 "hero_image" "images/about home.webp")
        hero_image_alt    = [string](Prop $v1 "hero_image_alt" "")
        hero_image_status = "temporary_placeholder"
        approved_images   = @()
        candidate_images  = @()
        usage_note        = "Only publish owned, licensed or explicitly authorized hotel imagery."
    }
}

# -----------------------------------------------------------------------
# SEO block
$displayName = [string]$identity.display_name
$destLabel   = [string]$location.location_label
$seo = [PSCustomObject]@{
    title       = "$displayName Guide | Tours, Transfers & Local Tips"
    description = "Plan your stay at $displayName with recommended tours, private airport transfers and local Guanacaste insight."
    keywords    = @(
        "$displayName tours",
        "$displayName transfer",
        "things to do near $displayName",
        "$destLabel travel guide"
    )
}

# -----------------------------------------------------------------------
# VERIFICATION block (carry over or create)
$v1Verification = Prop $v1 "verification" $null
$verification   = if ($v1Verification) {
    $v1Verification
} else {
    [PSCustomObject]@{
        status        = "pending"
        last_verified = (Get-Date -Format "yyyy-MM-dd")
        reviewer      = "Wild Papagayo Team"
        note          = "Migrated from schema v1. Hotel details should be verified before publication."
    }
}

# -----------------------------------------------------------------------
# WORKFLOW block
$v1Status    = [string](Prop $v1 "status"           "review")
$v1Editorial = [string](Prop $v1 "editorial_standard" "Wild Papagayo Hotel Gold Standard v2.0")
$workflow = [PSCustomObject]@{
    status               = $v1Status
    editorial_standard   = "Wild Papagayo Hotel Gold Standard v2.0"
    publication_threshold = 90
}

# -----------------------------------------------------------------------
# EXPERIENCE_STATUS block
$experience_status = [PSCustomObject]@{
    template         = "experience"
    editorial_version = "2.0"
    certification    = "pending"
}

# -----------------------------------------------------------------------
# Carry-over blocks (already in v1, compatible with v2)
$faq                 = @(Prop $v1 "faq"                 @())
$experienceHighlights= @(Prop $v1 "experience_highlights" @())
$localTips           = @(Prop $v1 "local_tips"           @())
$suggestedStay       = @(Prop $v1 "suggested_stay"       @())
$planning            = Prop $v1 "planning"            $null
$wildRecommendation  = Prop $v1 "wild_recommendation" $null
$relationships       = Prop $v1 "relationships"       $null

# -----------------------------------------------------------------------
# Assemble v2 document (field order matches Gold Standard)
$v2 = [PSCustomObject]@{
    template              = "experience"
    identity              = $identity
    location              = $location
    official_sources      = $officialSources
    official_facts        = $officialFacts
    editorial             = $editorial
    experience_highlights = $experienceHighlights
    local_tips            = $localTips
    suggested_stay        = $suggestedStay
    wild_recommendation   = $wildRecommendation
    planning              = $planning
    wild_insights         = $wildInsights
    traveler_profiles     = $travelerProfiles
    experience_scores     = $experienceScores
    gallery               = $gallery
    recommendations       = $recommendations
    faq                   = $faq
    seo                   = $seo
    verification          = $verification
    workflow              = $workflow
    experience_status     = $experience_status
}

if ($relationships) {
    $v2 | Add-Member -NotePropertyName "relationships" -NotePropertyValue $relationships
}

# -----------------------------------------------------------------------
# Report what changed
$movedFields   = @("id","name","slug","brand","category","luxury_level","destination_id","location_label","province","airport_id","tour_pickup_zone","transfer_minutes","description","hero_description","local_insight","featured_tours","related_articles","nearby_destinations","hotel_scores","status","editorial_standard","best_for","source_notes","official_url")
$newBlocks     = @("official_sources","official_facts","wild_insights","seo","experience_status","workflow")
$carriedBlocks = @("faq","experience_highlights","local_tips","suggested_stay","planning","wild_recommendation","gallery","verification","relationships")

Write-Host "  Remapped fields:"
foreach ($f in $movedFields) {
    if ($v1.PSObject.Properties[$f]) { Write-Host "    $f" }
}
Write-Host "  New blocks added:   $($newBlocks -join ', ')"
Write-Host "  Carried over:       $($carriedBlocks -join ', ')"
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN -- no file written." -ForegroundColor Yellow
    $v2 | ConvertTo-Json -Depth 20 | Write-Host
    exit 0
}

# --- Backup before overwrite ---
$backupPath = $filePath -replace '\.json$', (".v1-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
Copy-Item $filePath $backupPath
Write-Host "  Backup saved: $backupPath" -ForegroundColor DarkGray

$json = $v2 | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($filePath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host "Migration complete: $filePath" -ForegroundColor Green
Write-Host ""
Write-Host "Next step: run .\wild-intelligence-validator.ps1 -EntityType hotel -EntityId $HotelId"

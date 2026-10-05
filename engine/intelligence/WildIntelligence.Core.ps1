Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Read-JsonFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "JSON file not found: $Path" }
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "JSON file is empty: $Path" }
    return ($raw | ConvertFrom-Json)
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory=$true)]$Data,
        [Parameter(Mandatory=$true)][string]$Path,
        [int]$Depth = 30
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $json = $Data | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-ObjectPropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function ConvertTo-SafeArray {
    param($Value)
    if ($null -eq $Value) { Write-Output -NoEnumerate @(); return }
    Write-Output -NoEnumerate @($Value)
}

function Get-SourceStatusSummary {
    param($Sources)
    $result = @()
    foreach ($source in (ConvertTo-SafeArray $Sources)) {
        $status = [string](Get-ObjectPropertyValue $source 'status' 'pending')
        $result += [PSCustomObject]@{
            Type = [string](Get-ObjectPropertyValue $source 'type' 'unknown')
            Url = [string](Get-ObjectPropertyValue $source 'url' '')
            Status = $status
            LastChecked = [string](Get-ObjectPropertyValue $source 'last_checked' '')
        }
    }
    return @($result)
}

function Get-HotelQualityScore {
    param(
        [Parameter(Mandatory=$true)]$Master,
        [Parameter(Mandatory=$true)][string]$ProjectRoot
    )
    $sections = [ordered]@{}

    $identity           = Get-ObjectPropertyValue $Master 'identity'
    $location           = Get-ObjectPropertyValue $Master 'location'
    $officialFacts      = Get-ObjectPropertyValue $Master 'official_facts'
    $wildInsights       = Get-ObjectPropertyValue $Master 'wild_insights'
    $editorial          = Get-ObjectPropertyValue $Master 'editorial'
    $seo                = Get-ObjectPropertyValue $Master 'seo'
    $recommendations    = Get-ObjectPropertyValue $Master 'recommendations'
    $faq                = ConvertTo-SafeArray (Get-ObjectPropertyValue $Master 'faq')
    $verification       = Get-ObjectPropertyValue $Master 'verification'
    $sources            = ConvertTo-SafeArray (Get-ObjectPropertyValue $Master 'official_sources')
    $experienceHighlights = ConvertTo-SafeArray (Get-ObjectPropertyValue $Master 'experience_highlights')
    $localTips          = ConvertTo-SafeArray (Get-ObjectPropertyValue $Master 'local_tips')
    $suggestedStay      = ConvertTo-SafeArray (Get-ObjectPropertyValue $Master 'suggested_stay')
    $wildRecommendation = Get-ObjectPropertyValue $Master 'wild_recommendation'
    $transfer           = Get-ObjectPropertyValue $location 'transfer'

    # IDENTITY — 6 required fields
    $identityFields = @('id','official_name','slug','brand','category','luxury_level')
    $identityDone = 0
    foreach ($f in $identityFields) {
        if (-not [string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue $identity $f ''))) { $identityDone++ }
    }
    $sections['Identity'] = [math]::Round(($identityDone / $identityFields.Count) * 100)

    # LOCATION & TRANSFER — 4 fields + transfer block
    $locationFields = @('destination_id','province','airport_id','location_label')
    $locationDone = 0
    foreach ($f in $locationFields) {
        if (-not [string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue $location $f ''))) { $locationDone++ }
    }
    if ($transfer -and (Get-ObjectPropertyValue $transfer 'min') -and (Get-ObjectPropertyValue $transfer 'max')) { $locationDone++ }
    $sections['Location & Transfer'] = [math]::Round(($locationDone / 5) * 100)

    # OFFICIAL INFORMATION — source + key identity/location fields
    $officialScore = 0
    if ($sources.Count -gt 0)                                                                              { $officialScore += 20 }
    if (-not [string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue $identity 'brand' '')))         { $officialScore += 15 }
    if (-not [string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue $identity 'category' '')))      { $officialScore += 15 }
    if (-not [string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue $identity 'luxury_level' '')))  { $officialScore += 15 }
    if (-not [string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue $location 'airport_id' '')))    { $officialScore += 10 }
    if ($transfer -and (Get-ObjectPropertyValue $transfer 'min'))                                           { $officialScore += 10 }
    if (-not [string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue $location 'destination_id' ''))) { $officialScore += 10 }
    if (-not [string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue $officialFacts 'summary' '')))  { $officialScore += 5 }
    $sections['Official Information'] = [math]::Min(100, $officialScore)

    # WILD INSIGHTS — local_take + wild_recommendation + local_tips + suggested_stay
    $localTake = [string](Get-ObjectPropertyValue $wildInsights 'local_take' '')
    $wildScore = 0
    if ($localTake.Length -ge 50)      { $wildScore += 25 }
    if ($null -ne $wildRecommendation) { $wildScore += 25 }
    if ($localTips.Count -gt 0)        { $wildScore += 25 }
    if ($suggestedStay.Count -gt 0)    { $wildScore += 25 }
    $sections['Wild Insights'] = [math]::Min(100, $wildScore)

    # EXPERIENCE GUIDE — why_stay_here + highlights + tips + suggested_stay
    $whyStayHere    = Get-ObjectPropertyValue $editorial 'why_stay_here'
    $experienceScore = 100
    if ($null -eq $whyStayHere)              { $experienceScore -= 25 }
    if ($experienceHighlights.Count -eq 0)   { $experienceScore -= 25 }
    if ($localTips.Count -eq 0)              { $experienceScore -= 25 }
    if ($suggestedStay.Count -eq 0)          { $experienceScore -= 25 }
    $sections['Experience Guide'] = [math]::Max(0, $experienceScore)

    # SEO — title + description + keywords
    $seoScore = 0
    $seoTitle = [string](Get-ObjectPropertyValue $seo 'title' '')
    $seoDesc  = [string](Get-ObjectPropertyValue $seo 'description' '')
    if ($seoTitle.Length -gt 0) { $seoScore += 45 }
    if ($seoDesc.Length  -gt 0) { $seoScore += 45 }
    if ((ConvertTo-SafeArray (Get-ObjectPropertyValue $seo 'keywords')).Count -ge 3) { $seoScore += 10 }
    $sections['SEO'] = [math]::Min(100, $seoScore)

    # RECOMMENDATIONS — tours + articles
    $recTours    = ConvertTo-SafeArray (Get-ObjectPropertyValue $recommendations 'featured_tours')
    $recArticles = ConvertTo-SafeArray (Get-ObjectPropertyValue $recommendations 'related_articles')
    $recScore = 0
    if ($recTours.Count -ge 3)    { $recScore += 65 } elseif ($recTours.Count -gt 0) { $recScore += 40 }
    if ($recArticles.Count -ge 1) { $recScore += 35 }
    $sections['Recommendations'] = [math]::Min(100, $recScore)

    # FAQ — 3 or more = 100%
    $sections['FAQ'] = if ($faq.Count -ge 3) { 100 } elseif ($faq.Count -gt 0) { 45 } else { 0 }

    # VERIFICATION — reviewed/verified/approved status = 100%
    $verStatus = [string](Get-ObjectPropertyValue $verification 'status' '')
    $sections['Verification'] = if ($verStatus -match 'reviewed|verified|approved') { 100 } else { 0 }

    $values  = @($sections.Values | ForEach-Object { [double]$_ })
    $overall = if ($values.Count -gt 0) { [math]::Round(($values | Measure-Object -Average).Average, 1) } else { 0 }

    return [PSCustomObject]@{ Sections = $sections; Overall = $overall }
}

function Convert-MasterToLegacyHotel {
    param([Parameter(Mandatory=$true)]$Master)
    $identity = $Master.identity
    $location = $Master.location
    $gallery = $Master.gallery
    $wild = $Master.wild_insights
    $recs = $Master.recommendations
    $scores = $Master.experience_scores
    $verification = $Master.verification

    return [ordered]@{
        id = $identity.id
        name = $identity.official_name
        slug = $identity.slug
        brand = $identity.brand
        category = $identity.category
        luxury_level = $identity.luxury_level
        destination_id = $location.destination_id
        location_label = $location.location_label
        province = $location.province
        airport_id = $location.airport_id
        transfer_minutes = [ordered]@{
            min = $location.transfer.min
            max = $location.transfer.max
            label = $location.transfer.label
            source_type = $location.transfer.source_type
        }
        transfer_by_airport = Get-ObjectPropertyValue $location 'transfer_by_airport' $null
        coordinates = Get-ObjectPropertyValue $location 'coordinates' $null
        formatted_address = Get-ObjectPropertyValue $location 'formatted_address' $null
        tour_pickup_zone = $location.tour_pickup_zone
        official_url = $Master.official_sources[0].url
        hero_image = $gallery.hero_image
        hero_image_alt = $gallery.hero_image_alt
        hero_image_status = $gallery.hero_image_status
        description = $Master.editorial.description
        hero_description = $Master.editorial.hero_description
        local_insight = $wild.local_take
        best_for = @($Master.traveler_profiles)
        hotel_scores = $scores
        featured_tours = @($recs.featured_tours)
        related_articles = @($recs.related_articles)
        nearby_destinations = @($recs.nearby_destinations)
        excursion_guide = @(Get-ObjectPropertyValue $recs 'excursion_guide' @())
        excursion_intro = Get-ObjectPropertyValue $recs 'excursion_intro' ''
        suppress_curated_experiences = [bool](Get-ObjectPropertyValue $recs 'suppress_curated_experiences' $false)
        suppress_private_tours_intro = [bool](Get-ObjectPropertyValue $recs 'suppress_private_tours_intro' $false)
        suppress_restaurants_section = [bool](Get-ObjectPropertyValue $recs 'suppress_restaurants_section' $false)
        transfer_landing_url = Get-ObjectPropertyValue $recs 'transfer_landing_url' ''
        faq = @($Master.faq)
        amenities = @(Get-ObjectPropertyValue $Master 'amenities' @())
        room_types = @(Get-ObjectPropertyValue $Master 'room_types' @())
        traveler_profile_reasons = @(Get-ObjectPropertyValue $Master 'traveler_profile_reasons' @())
        google_reviews = Get-ObjectPropertyValue $Master 'google_reviews' $null
        official_sources = @($Master.official_sources)
        official_facts = $Master.official_facts
        wild_insights = $wild
        status = $Master.workflow.status
        verification = $verification
        editorial_standard = $Master.workflow.editorial_standard
        expedia_affiliate_link = $(
            $booking = Get-ObjectPropertyValue $Master 'booking' $null
            if ($booking) { Get-ObjectPropertyValue $booking 'expedia_affiliate_link' '' } else { '' }
        )
        seo_title_override = $(
            $seoObj = Get-ObjectPropertyValue $Master 'seo' $null
            if ($seoObj) { Get-ObjectPropertyValue $seoObj 'title' '' } else { '' }
        )
        seo_description_override = $(
            $seoObj = Get-ObjectPropertyValue $Master 'seo' $null
            if ($seoObj) { Get-ObjectPropertyValue $seoObj 'description' '' } else { '' }
        )
        # Verified factual attributes (adults_only, all_inclusive_type, beach_relationship,
        # on_property_dining_count, positioning_evidence, evidence_sources, fact_evidence).
        # Passed through as-is -- absent on master when not yet researched, which must mean
        # absent here too, not null or a placeholder object.
        factual_attributes = Get-ObjectPropertyValue $Master 'factual_attributes' $null
        # Temporary operational status (e.g. a property closed for renovation) -- deliberately
        # separate from factual_attributes, which represents durable property facts, not a
        # transient availability condition. Absent on master when nothing is in effect, which
        # must mean absent here too, so every page this feeds renders nothing by default.
        operational_notice = Get-ObjectPropertyValue $Master 'operational_notice' $null
    }
}

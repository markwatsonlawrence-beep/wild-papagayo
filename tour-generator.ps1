# ============================================================
# Wild Papagayo - Tour Page Generator v1.0
# Generates tours/*.html from knowledge/tours/*.json, using the
# real, hand-extracted page_content field (hero copy, experience
# highlights, accordions, pricing tiers, testimonials, cross-sell)
# captured from the original hand-crafted pages -- this generator
# reproduces that real content, it does not invent new content.
# Usage: .\tour-generator.ps1
# ============================================================

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Write-FileIfChanged {
    param([string]$Path, [string]$Content)
    if ((Test-Path $Path) -and ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) -ceq $Content)) { return }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}
function Get-SeoDescription {
    param([string]$Text, [int]$MaxLen = 150)
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.Length -le $MaxLen) { return $Text }
    $slice = $Text.Substring(0, $MaxLen)
    $lastPeriod = $slice.LastIndexOf('. ')
    if ($lastPeriod -gt 60) { return $slice.Substring(0, $lastPeriod + 1).Trim() }
    $lastComma = $slice.LastIndexOf(', ')
    if ($lastComma -gt 60) { return ($slice.Substring(0, $lastComma).TrimEnd() + '.') }
    $lastSpace = $slice.LastIndexOf(' ')
    if ($lastSpace -gt 0) { $slice = $slice.Substring(0, $lastSpace) }
    return ($slice.TrimEnd(',',';',':','-',' ') + '.')
}

function Get-SeoTitle {
    param([string]$Name, [int]$MaxLen = 60)
    $suffix = ' | Wild Papagayo'
    $needsRegion = $Name -notmatch 'Costa Rica'
    $region = if ($needsRegion) { ', Costa Rica' } else { '' }
    $budget = $MaxLen - $suffix.Length - $region.Length
    $short = $Name
    $emDashSep = ' ' + [char]0x2014 + ' '
    $dashIdx = $Name.IndexOf($emDashSep)
    if ($dashIdx -gt 0) { $short = $Name.Substring(0, $dashIdx) }
    if ($short.Length -gt $budget) {
        $slice = $short.Substring(0, $budget)
        $lastSpace = $slice.LastIndexOf(' ')
        if ($lastSpace -gt 0) { $slice = $slice.Substring(0, $lastSpace) }
        $connectors = @('and','&','at','of','the','with','for','in','a','to','on',[string]([char]0x2014))
        $words = [System.Collections.Generic.List[string]]($slice -split ' ')
        while ($words.Count -gt 1 -and $connectors -contains $words[$words.Count - 1].ToLower().TrimEnd(',',';',':','-')) {
            $words.RemoveAt($words.Count - 1)
        }
        $short = ($words -join ' ').TrimEnd(',',';',':','-',' ',[char]0x2014)
    }
    return "$short$region$suffix"
}

$root = $PSScriptRoot
$tourDir = Join-Path $root "knowledge\tours"
$templatePath = Join-Path $root "templates\tour.html"
$outDir = Join-Path $root "tours"
$siteUrl = "https://wildpapagayo.com"

# Related Articles -- reuses the exact pattern already proven in production on
# hotel pages (hotel-generator.ps1): curated slugs first, then automatic
# tour_ids matches, deduped, capped at 3. No generic fallback -- a tour with
# no real match renders nothing.
$blogDataPath = Join-Path $root "blog-data.json"
$allBlogArticles = if (Test-Path $blogDataPath) { @(([System.IO.File]::ReadAllText($blogDataPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)) } else { @() }
$tourRelatedStats = New-Object System.Collections.Generic.List[object]
$invalidRelatedSlugs = New-Object System.Collections.Generic.List[object]

# Real width/height per image, extracted from the actual .webp files by
# get-image-dimensions.js -- used so <img> tags carry real dimensions instead
# of guesses, preventing layout shift without fabricating values.
$dimensionsPath = Join-Path $root "image-dimensions.json"
$imageDimensions = if (Test-Path $dimensionsPath) { [System.IO.File]::ReadAllText($dimensionsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } else { $null }
function Get-ImageDimAttrs {
    param([string]$Src)
    if ($null -eq $imageDimensions) { return '' }
    $fileName = [System.IO.Path]::GetFileName($Src)
    $prop = $imageDimensions.PSObject.Properties[$fileName]
    if ($null -eq $prop) { return '' }
    return ' width="' + [string]$prop.Value.width + '" height="' + [string]$prop.Value.height + '"'
}

function Read-Utf8Json {
    param([string]$Path)
    return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}
function Get-PropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}
# Resolves one FAQ item's effective answer text. A tour's own `answer` is used verbatim UNLESS the
# item carries `answer_source: "central_policy:cancellation_faq"`, in which case the policy file's
# cancellation_faq.answer wins -- this is what lets ~25 tours share one centrally-maintained answer
# without duplicating the text into each knowledge/tours/<slug>.json. Every other FAQ on every tour
# is completely untouched by this.
function Get-FaqAnswer {
    param($FaqItem, [string]$CentralAnswer)
    $source = [string](Get-PropertyValue $FaqItem 'answer_source' '')
    if ($source -eq 'central_policy:cancellation_faq') { return $CentralAnswer }
    return [string]$FaqItem.answer
}
function ConvertTo-HtmlSafe {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    return $Text.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}
# Some extracted fields intentionally keep inline tags (e.g. <strong>, <br>) that
# were part of the real page copy -- these must NOT be escaped, only the plain
# text fields (titles, alt text, meta) go through ConvertTo-HtmlSafe.

New-Item -ItemType Directory -Force $outDir | Out-Null
$template = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)

# Commercial pricing source of truth (Excel -> tour-pricing.json). Public
# "From $X" prices, guest-tier qualifiers, and disclaimer copy are derived
# from here -- never from the deprecated page_content.pricing_tiers.options[].
# price/note or pricing.from_price fields (kept in knowledge/tours/*.json for
# now, but no longer read for public price rendering).
#
# A tour/option is only migrated to this derived-pricing path once its
# page_content.pricing_tiers.options[] entry carries an explicit option_id
# that resolves against tour-pricing.json -- Tour Slug + Option ID is the
# only authoritative key, never array position, heading, badge or display
# label. Options without option_id keep rendering from the legacy fields
# unchanged, which is what scopes a partial rollout (e.g. a single pilot
# tour) without needing a separate CLI filter.
$pricingJsonPath = Join-Path $root "tour-pricing.json"
if (-not (Test-Path $pricingJsonPath)) {
    throw "tour-pricing.json not found -- cannot generate tour pages without the commercial pricing source. Run 'npm run pricing:convert' first."
}
$pricingData = Read-Utf8Json $pricingJsonPath

# Booking & cancellation policy source of truth (single central file, replacing the 33 independent
# per-tour copies that used to live in knowledge/tours/<slug>.json). Loaded once, validated up front,
# and fails the whole build rather than silently falling back to stale/missing policy text -- same
# fail-safe posture as the pricing source above.
$policyJsonPath = Join-Path $root "knowledge\policies\booking-cancellation.json"
if (-not (Test-Path $policyJsonPath)) {
    throw "knowledge/policies/booking-cancellation.json not found -- cannot generate tour pages without the central booking/cancellation policy source."
}
$policyData = Read-Utf8Json $policyJsonPath
$policyVersion = Get-PropertyValue $policyData 'version' $null
$policyCore = [string](Get-PropertyValue $policyData 'reservation_policy_core' '')
$policyNoshow = [string](Get-PropertyValue $policyData 'reservation_policy_noshow' '')
$policyFaq = Get-PropertyValue $policyData 'cancellation_faq' $null
$policyFaqQuestion = [string](Get-PropertyValue $policyFaq 'question' '')
$policyFaqAnswer = [string](Get-PropertyValue $policyFaq 'answer' '')
if ($null -eq $policyVersion) { throw "knowledge/policies/booking-cancellation.json: missing 'version'." }
if (-not $policyCore) { throw "knowledge/policies/booking-cancellation.json: missing or empty 'reservation_policy_core'." }
if (-not $policyNoshow) { throw "knowledge/policies/booking-cancellation.json: missing or empty 'reservation_policy_noshow'." }
if (-not $policyFaqQuestion -or -not $policyFaqAnswer) { throw "knowledge/policies/booking-cancellation.json: 'cancellation_faq' must have both a non-empty 'question' and 'answer'." }

# Pickup-zone display names for the trust-bar (S1 fix) -- reuses the existing
# destination taxonomy rather than duplicating a location-name list in code.
$destinationsJsonPath = Join-Path $root "knowledge\destinations.json"
$destinationNameById = @{}
if (Test-Path $destinationsJsonPath) {
    $destinationsData = Read-Utf8Json $destinationsJsonPath
    foreach ($dest in @($destinationsData)) {
        $destId = [string](Get-PropertyValue $dest 'id' '')
        $destName = [string](Get-PropertyValue $dest 'name' '')
        if ($destId -and $destName) { $destinationNameById[$destId] = $destName }
    }
}

function Get-DerivedPriceInfo {
    # Resolves an estimator option's minimum public per-person price and
    # which guest tier(s) produce it. Throws (fails the build) rather than
    # guessing whenever the data can't support a confident public price --
    # matches the project-wide rule that missing/ambiguous pricing must
    # never silently render as $0, a wrong number, or a stale legacy value.
    param($EstOpt, [string]$TourId, [string]$OptionId)
    if ($EstOpt.estimator_status -eq 'manual_quote') {
        return [pscustomobject]@{ isManualQuote = $true; price = $null; guestLabels = @(); zoneApplies = $null }
    }
    if ($EstOpt.estimator_status -ne 'active') {
        throw "Tour '$TourId' option '$OptionId': unrecognized estimator_status '$($EstOpt.estimator_status)' in tour-pricing.json."
    }
    $zoneApplies = $EstOpt.zone_adjustment_applies
    if ($zoneApplies -isnot [bool]) {
        throw "Tour '$TourId' option '$OptionId': zone_adjustment_applies is not an explicit boolean (found: '$zoneApplies'). Refusing to render a public price without a confirmed zone policy -- fix tour-pricing.json/the Excel source."
    }
    $tiers = @()
    if ($null -ne $EstOpt.pp_2)     { $tiers += [pscustomobject]@{ label = '2';  value = [double]$EstOpt.pp_2 } }
    if ($null -ne $EstOpt.pp_3)     { $tiers += [pscustomobject]@{ label = '3';  value = [double]$EstOpt.pp_3 } }
    if ($null -ne $EstOpt.pp_4plus) { $tiers += [pscustomobject]@{ label = '4+'; value = [double]$EstOpt.pp_4plus } }
    if ($tiers.Count -eq 0) {
        throw "Tour '$TourId' option '$OptionId': estimator_status is 'active' but no pp_2/pp_3/pp_4plus pricing is present in tour-pricing.json."
    }
    $minVal = ($tiers | Measure-Object -Property value -Minimum).Minimum
    $guestLabels = @($tiers | Where-Object { $_.value -eq $minVal } | ForEach-Object { $_.label })
    return [pscustomobject]@{ isManualQuote = $false; price = $minVal; guestLabels = $guestLabels; zoneApplies = $zoneApplies }
}

function Format-GuestPhrase {
    param([string[]]$GuestLabels)
    return 'groups of ' + ($GuestLabels -join ' or ') + ' guests'
}

function Format-DerivedPrice {
    param([double]$Value)
    if ($Value -eq [Math]::Floor($Value)) { return [string]([int]$Value) }
    return [string]$Value
}

function Get-PricingDisclaimer {
    param([Parameter(Mandatory)][pscustomobject]$PriceInfo)
    if ($PriceInfo.isManualQuote) {
        return 'Pricing and availability require confirmation. Request a personalized quote below.'
    }
    if ($PriceInfo.zoneApplies -eq $false) {
        return 'Private pricing varies by group size. Get your personalized estimate below.'
    }
    return 'Private pricing varies by group size and pickup location. Get your personalized estimate below.'
}

# Collected during generation, checked after every file is written: for each
# derived price actually rendered, confirm the exact dollar amount written to
# disk -- looked up deterministically via data-option-id, never by scanning
# for arbitrary "$" text -- matches what was computed from tour-pricing.json.
# This is what stops a future code change from silently reintroducing a
# legacy/stale price without anyone noticing.
$priceValidationChecks = New-Object System.Collections.Generic.List[object]
$schemaPriceMismatches = New-Object System.Collections.Generic.List[object]

$files = Get-ChildItem $tourDir -Filter "*.json" -File | Sort-Object Name
$generated = 0
$skipped = @()

# ---- Production scope guard ----
# The "absent from tour-pricing.json -> skip this tour's regeneration"
# mechanism below is only safe because exactly one currently-published tour
# (slothadventure, Estimator Status = INACTIVE) is expected to be absent.
# It must never silently become a catch-all for a tour that was supposed to
# ship but got dropped by a bad Excel edit or a broken converter run --
# that would silently freeze a tour's public price on stale legacy data
# with no warning. Verify the exact expected release shape up front and
# abort the whole build if it doesn't match.
$expectedExcludedTours = @()
$expectedActiveTourCount = 32
$expectedManualQuoteTours = @('ostionalturtles')

$allTourIds = @($files | ForEach-Object { [string](Read-Utf8Json $_.FullName).id })
$pricingTourIds = @($pricingData.tours.PSObject.Properties.Name)

$missingFromPricing = @($allTourIds | Where-Object { $pricingTourIds -notcontains $_ })
$unexpectedlyMissing = @($missingFromPricing | Where-Object { $expectedExcludedTours -notcontains $_ })
if ($unexpectedlyMissing.Count -gt 0) {
    throw "Scope guard failed: published tour(s) unexpectedly absent from tour-pricing.json (would otherwise be silently skipped): $($unexpectedlyMissing -join ', '). Absence from tour-pricing.json must never be a silent-skip mechanism for a tour that was supposed to ship -- fix the Excel/converter output before regenerating."
}
$expectedButPresent = @($expectedExcludedTours | Where-Object { $missingFromPricing -notcontains $_ })
if ($expectedButPresent.Count -gt 0) {
    throw "Scope guard failed: tour(s) expected to be excluded are now present in tour-pricing.json: $($expectedButPresent -join ', '). If this is an intentional onboarding (e.g. slothadventure going ACTIVE), update `$expectedExcludedTours in tour-generator.ps1 deliberately -- do not let this pass silently."
}

$manualQuoteTourIds = @($pricingTourIds | Where-Object {
    $entry = Get-PropertyValue $pricingData.tours $_ $null
    @($entry.options) | Where-Object { $_.estimator_status -eq 'manual_quote' } | Select-Object -First 1
})
$activeTourIds = @($pricingTourIds | Where-Object { $manualQuoteTourIds -notcontains $_ })

$manualQuoteJoined = (@($manualQuoteTourIds | Sort-Object)) -join ','
$expectedManualQuoteJoined = (@($expectedManualQuoteTours | Sort-Object)) -join ','
if ($manualQuoteJoined -ne $expectedManualQuoteJoined) {
    throw "Scope guard failed: expected MANUAL QUOTE tour(s) [$($expectedManualQuoteTours -join ', ')], found [$($manualQuoteTourIds -join ', ')]."
}
if ($activeTourIds.Count -ne $expectedActiveTourCount) {
    throw "Scope guard failed: expected exactly $expectedActiveTourCount ACTIVE tours in tour-pricing.json, found $($activeTourIds.Count): $($activeTourIds -join ', ')"
}
if ($pricingTourIds.Count -ne ($expectedActiveTourCount + $expectedManualQuoteTours.Count)) {
    throw "Scope guard failed: expected exactly $($expectedActiveTourCount + $expectedManualQuoteTours.Count) tours total in tour-pricing.json, found $($pricingTourIds.Count)."
}
Write-Host "Scope guard passed: $($pricingTourIds.Count) tours in tour-pricing.json ($($activeTourIds.Count) ACTIVE + $($manualQuoteTourIds.Count) MANUAL QUOTE), $($expectedExcludedTours.Count) intentionally excluded ($($expectedExcludedTours -join ', '))." -ForegroundColor Green

foreach ($file in $files) {
    $tour = Read-Utf8Json $file.FullName
    $id = [string]$tour.id
    $pc = Get-PropertyValue $tour 'page_content' $null
    if (-not $pc) { $skipped += "$id (no page_content -- run the extraction step first)"; continue }

    # Tours not present in tour-pricing.json's production estimator dataset
    # (currently only slothadventure -- Estimator Status = INACTIVE) are
    # skipped entirely: their tours/*.html is never touched by this run, not
    # even regenerated with unrelated/unrelated-to-pricing content. This is
    # a permanent, data-driven rule (keyed off tour-pricing.json membership,
    # never a hardcoded slug) -- it replaces the earlier manual
    # "regenerate everything, then restore the excluded file from a backup"
    # workflow, which was never meant to be the long-term process.
    if (-not (Get-PropertyValue $pricingData.tours $id $null)) {
        $skipped += "$id (not present in tour-pricing.json production dataset -- tours/$id.html left untouched)"
        continue
    }

    $name = [string]$tour.name
    $slug = [string]$tour.slug
    $shortDesc = [string]$tour.short_description
    $heroImage = [string]$tour.hero_image
    $heroImageAlt = [string]$tour.hero_image_alt
    $heroImageDim = Get-ImageDimAttrs $heroImage
    $canonical = "$siteUrl/tours/$slug"

    # ---- Head / SEO ----
    # Optional per-tour overrides, root-level only -- when absent, falls back to the auto-generated
    # title/description derived from name/short_description. A page_content-nested second-choice
    # location existed historically (some tours were authored with the override nested there by
    # editorial mistake); all 33 tours were migrated to the root-level field and that fallback was
    # retired -- see knowledge/tour-schema.json, which documents root-level seo_title_override /
    # seo_description_override as the single canonical location. Do not reintroduce a nested copy.
    $seoTitleOverride = [string](Get-PropertyValue $tour 'seo_title_override' '')
    $seoTitle = if ($seoTitleOverride) { $seoTitleOverride } else { Get-SeoTitle $name }
    $seoDescOverride = [string](Get-PropertyValue $tour 'seo_description_override' '')
    $seoDesc = if ($seoDescOverride) { $seoDescOverride } else { Get-SeoDescription $shortDesc }
    $ogImage = "$siteUrl/$heroImage"

    $breadcrumb = [ordered]@{
        "@type"="BreadcrumbList"
        itemListElement=@(
            [ordered]@{"@type"="ListItem";position=1;name="Home";item="$siteUrl/"}
            [ordered]@{"@type"="ListItem";position=2;name="Tours";item="$siteUrl/tours"}
            [ordered]@{"@type"="ListItem";position=3;name=$name;item=$canonical}
        )
    }
    $touristTrip = [ordered]@{
        "@type"="TouristTrip"
        "@id"="$canonical-tour"
        name=$name
        description=$shortDesc
        url=$canonical
        provider=[ordered]@{"@type"="TravelAgency";"@id"="$siteUrl/#organization";name="Wild Papagayo"}
        image=$ogImage
        availableLanguage=@("en","es")
    }
    # pricing.from_price / pricing.price_confirmed -- read here only for the
    # teaser's own legacy fallback below (an unmigrated tour with no
    # tour-pricing.json options at all). The JSON-LD Offer.price itself no
    # longer uses these: it's computed further below from the same
    # tour-pricing.json-derived minimum price as the public teaser (see
    # "Schema Offer.price" after the Pricing section). $schema is also
    # finalized there; nothing between here and there reads either variable.
    $pricingBlock = Get-PropertyValue $tour 'pricing' $null
    $canonicalFromPrice = Get-PropertyValue $pricingBlock 'from_price' $null
    $priceConfirmed = [bool](Get-PropertyValue $pricingBlock 'price_confirmed' $false)

    # ---- Hero ----
    $heroRegion = [string](Get-PropertyValue $pc 'hero_region_label' $tour.category)
    $heroTitleHtml = [string](Get-PropertyValue $pc 'hero_title_html' $name)
    $chips = @(Get-PropertyValue $pc 'hero_chips' @())
    $heroChipsHtml = ($chips | ForEach-Object { "<span>$_</span>" }) -join ''
    $heroSubtitle = [string](Get-PropertyValue $pc 'hero_subtitle_html' '')
    $heroSubtitleHtml = if ($heroSubtitle) { '<p class="ths-subtitle">' + $heroSubtitle + '</p>' } else { '' }

    # ---- Pickup areas (S1 fix) ----
    # A. page_content.pickup_areas, when present, is a per-tour, ops-authored
    #    breakdown (area label + hotels/notes) -- rendered exactly as before.
    # B. Otherwise, map this tour's own pickup_zone_ids to display names via
    #    knowledge/destinations.json and render only those zones -- never a
    #    location unconnected to this tour's actual data.
    # C. If pickup_zone_ids is empty or none of its ids resolve, fall back to
    #    neutral wording rather than any hardcoded location list.
    $pickupAreas = @(Get-PropertyValue $pc 'pickup_areas' @())
    if ($pickupAreas.Count -gt 0) {
        $pickupAreasHtml = ($pickupAreas | ForEach-Object {
            $hotels = (@($_.hotels) | ForEach-Object { ConvertTo-HtmlSafe $_ }) -join ' &middot; '
            '<div class="pickup-area"><b>' + (ConvertTo-HtmlSafe $_.area) + '</b><span>' + $hotels + '</span></div>'
        }) -join "`n"
    } else {
        $tourPickupZoneIds = @(Get-PropertyValue $tour 'pickup_zone_ids' @())
        $mappedZoneNames = @($tourPickupZoneIds | ForEach-Object {
            $zoneId = [string]$_
            if ($destinationNameById.ContainsKey($zoneId)) { $destinationNameById[$zoneId] }
        } | Where-Object { $_ })
        if ($mappedZoneNames.Count -gt 0) {
            $pickupAreasHtml = '<div class="ths-trust-hotels">' + (($mappedZoneNames | ForEach-Object { ConvertTo-HtmlSafe $_ }) -join ' &middot; ') + '</div>'
        } else {
            $pickupAreasHtml = '<div class="ths-trust-hotels">Private pickup available from selected Guanacaste resorts.</div>'
        }
    }

    # ---- Peak season note (optional, only when operationally true) ----
    $peakSeasonNote = [string](Get-PropertyValue $pc 'peak_season_note' '')
    $peakSeasonHtml = if ($peakSeasonNote) { '<p class="tour-peak-season">&#9889; ' + (ConvertTo-HtmlSafe $peakSeasonNote) + '</p>' } else { '' }

    # ---- Tour at a Glance (optional -- empty/absent tours render nothing) ----
    $glanceItems = @(Get-PropertyValue $pc 'tour_at_a_glance' @())
    $glanceHtml = ""
    if ($glanceItems.Count -gt 0) {
        $glanceCardsHtml = ($glanceItems | ForEach-Object {
            '<div class="glance-item"><div class="glance-icon">' + $_.icon + '</div><b>' + (ConvertTo-HtmlSafe $_.label) + '</b><span>' + (ConvertTo-HtmlSafe $_.value) + '</span></div>'
        }) -join "`n"
        $glanceNote = [string](Get-PropertyValue $pc 'tour_at_a_glance_note' '')
        $glanceNoteHtml = if ($glanceNote) { '<p class="tour-glance-note">' + (ConvertTo-HtmlSafe $glanceNote) + '</p>' } else { '' }
        $glanceHtml = '<div class="tour-glance-bar reveal"><div class="tour-glance-grid">' + $glanceCardsHtml + '</div>' + $glanceNoteHtml + '</div>'
    }

    # ---- Gallery ----
    $gallery = @(Get-PropertyValue $pc 'gallery' @())
    $galleryMainHtml = ($gallery | ForEach-Object {
        '<img alt="' + (ConvertTo-HtmlSafe $_.alt) + '" src="../' + $_.src.TrimStart('.','/').Replace('images/','images/') + '" loading="lazy" decoding="async">'
    }) -join "`n"
    # gallery.src already stored as "../images/x.webp" from extraction -- fix double-prefix risk
    $galleryMainHtml = ($gallery | ForEach-Object {
        $src = [string]$_.src
        if (-not $src.StartsWith('..')) { $src = "../$src" }
        '<img alt="' + (ConvertTo-HtmlSafe $_.alt) + '" src="' + $src + '"' + (Get-ImageDimAttrs $src) + ' loading="lazy" decoding="async">'
    }) -join "`n"
    $galleryThumbsHtml = ($gallery | ForEach-Object {
        $src = [string]$_.src
        if (-not $src.StartsWith('..')) { $src = "../$src" }
        '<button type="button"><img alt="' + (ConvertTo-HtmlSafe $_.alt) + '" src="' + $src + '"' + (Get-ImageDimAttrs $src) + ' loading="lazy" decoding="async"></button>'
    }) -join "`n"

    # ---- Why Explore Privately (universal Wild Papagayo brand block, same on every tour) ----
    $whyPrivateSection = '<section class="why-private-section"><div class="container"><div class="section-head reveal"><span class="section-kicker">Why It Matters</span><h2 class="section-title">Why Explore Privately?</h2></div><div class="why-private-grid"><div class="why-private-item reveal"><h3>Your Own Vehicle</h3><p>Travel comfortably without sharing transportation with other groups.</p></div><div class="why-private-item reveal"><h3>Direct Hotel Pickup</h3><p>Start and end the experience directly at your resort. No shared buses, no unnecessary hotel stops.</p></div><div class="why-private-item reveal"><h3>Personal Attention</h3><p>Enjoy more interaction with your certified local guide.</p></div><div class="why-private-item reveal"><h3>A Better Pace</h3><p>Spend your day experiencing Costa Rica instead of waiting on a large group.</p></div><div class="why-private-item reveal"><h3>Local Support</h3><p>Your Wild Papagayo concierge helps coordinate every detail before your tour.</p></div></div></div></section>'

    # ---- Experience section ----
    $exp = Get-PropertyValue $pc 'experience_section' $null
    $experienceSectionHtml = ""
    if ($exp -and $exp.title) {
        $itemsHtml = (@(Get-PropertyValue $exp 'items' @()) | ForEach-Object {
            '<div class="experience-item"><div class="experience-icon">' + $_.icon + '</div><h3>' + (ConvertTo-HtmlSafe $_.title) + '</h3><p>' + (ConvertTo-HtmlSafe $_.description) + '</p></div>'
        }) -join "`n"
        $footer = Get-PropertyValue $exp 'footer' $null
        $footerHtml = ""
        if ($footer -and $footer.title) {
            $footerHtml = '<div class="experience-footer"><div class="experience-highlight"><span>' + $footer.icon + '</span><div><h3>' + (ConvertTo-HtmlSafe $footer.title) + '</h3><p>' + (ConvertTo-HtmlSafe $footer.text) + '</p></div></div></div>'
        }
        $experienceSectionHtml = '<div class="info-panel reveal" style="grid-column:1/-1;"><span class="section-tag">' + (ConvertTo-HtmlSafe $exp.tag) + '</span><h2>' + (ConvertTo-HtmlSafe $exp.title) + '</h2><p class="experience-intro">' + (ConvertTo-HtmlSafe $exp.intro) + '</p><div class="experience-grid">' + $itemsHtml + '</div>' + $footerHtml + '</div>'
    }

    # ---- Step-by-step itinerary (optional) ----
    $itinerarySteps = @(Get-PropertyValue $pc 'itinerary_steps' @())
    $itineraryHtml = ""
    if ($itinerarySteps.Count -gt 0) {
        $stepBlocks = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $itinerarySteps.Count; $i++) {
            $step = $itinerarySteps[$i]
            $num = ('{0:D2}' -f ($i + 1))
            $stepBlocks.Add('<div class="itinerary-step reveal"><div class="itinerary-step-num">' + $num + '</div><div class="itinerary-step-body"><h3>' + (ConvertTo-HtmlSafe $step.title) + '</h3><p>' + (ConvertTo-HtmlSafe $step.text) + '</p></div></div>')
        }
        $itineraryHtml = '<div class="info-panel reveal" style="grid-column:1/-1;"><span class="section-tag">Your Day, Step by Step</span><h2>What to Expect</h2><div class="itinerary-steps-stack">' + ($stepBlocks -join "`n") + '</div></div>'
    }

    # ---- FAQ (optional) ----
    $faqItems = @(Get-PropertyValue $pc 'faq' @())
    $faqHtml = ""
    $faqSchema = $null
    if ($faqItems.Count -gt 0) {
        $faqBlocks = ($faqItems | ForEach-Object {
            $answer = Get-FaqAnswer $_ $policyFaqAnswer
            '<div class="accordion-item"><button class="accordion-trigger"><span>' + (ConvertTo-HtmlSafe $_.question) + '</span><b aria-hidden="true">&#8964;</b></button><div class="accordion-content"><p>' + (ConvertTo-HtmlSafe $answer) + '</p></div></div>'
        }) -join "`n"
        $faqHtml = '<div class="info-panel reveal" style="grid-column:1/-1;"><span class="section-tag">Good to Know</span><h2>Frequently Asked Questions</h2><div class="accordion-stack clean-stack">' + $faqBlocks + '</div></div>'
        $faqEntities = $faqItems | ForEach-Object {
            $answer = Get-FaqAnswer $_ $policyFaqAnswer
            [ordered]@{"@type"="Question";name=[string]$_.question;acceptedAnswer=[ordered]@{"@type"="Answer";text=$answer}}
        }
        $faqSchema = [ordered]@{"@context"="https://schema.org";"@type"="FAQPage";mainEntity=@($faqEntities)} | ConvertTo-Json -Depth 10 -Compress
    }
    $faqSchemaTag = if ($faqSchema) { '<script type="application/ld+json">' + $faqSchema + '</script>' } else { '' }

    # ---- Related Articles ("Travel insights") ----
    $curatedSlugList = @(Get-PropertyValue $tour 'related_article_slugs' @())
    $curatedArticles = New-Object System.Collections.Generic.List[object]
    foreach ($curSlug in $curatedSlugList) {
        $match = $allBlogArticles | Where-Object { $_.slug -eq $curSlug } | Select-Object -First 1
        if ($match) {
            $curatedArticles.Add($match)
        } else {
            $invalidRelatedSlugs.Add([pscustomobject]@{ tour = $id; slug = $curSlug })
            Write-Warning "Invalid related_article_slugs entry on '$id': '$curSlug' does not exist in blog-data.json -- skipped, no link rendered."
        }
    }
    $autoMatches = @($allBlogArticles | Where-Object { @(Get-PropertyValue $_ 'tour_ids' @()) -contains $id })
    $seenRelatedSlugs = New-Object System.Collections.Generic.HashSet[string]
    $relatedArticleEntries = New-Object System.Collections.Generic.List[object]
    foreach ($art in $curatedArticles) {
        if ($seenRelatedSlugs.Add([string]$art.slug)) {
            $relatedArticleEntries.Add([pscustomobject]@{ article = $art; reason = 'CURATED' })
        }
    }
    foreach ($art in $autoMatches) {
        if ($seenRelatedSlugs.Add([string]$art.slug)) {
            $relatedArticleEntries.Add([pscustomobject]@{ article = $art; reason = 'TOUR_ID_MATCH' })
        }
    }
    $relatedArticleEntries = @($relatedArticleEntries | Select-Object -First 3)
    $tourRelatedStats.Add([pscustomobject]@{ tour = $id; entries = $relatedArticleEntries })

    $relatedArticlesHtml = ""
    if ($relatedArticleEntries.Count -gt 0) {
        $riCards = ($relatedArticleEntries | ForEach-Object {
            $art = $_.article
            $artImg = if ($art.image_top) { $art.image_top } else { $tour.hero_image }
            '<a class="ti-card" href="../blog/' + (ConvertTo-HtmlSafe $art.slug) + '"><img src="../' + (ConvertTo-HtmlSafe $artImg) + '" alt="' + (ConvertTo-HtmlSafe $art.image_top_alt) + '" loading="lazy" decoding="async"><div class="ti-card-body"><span class="ti-card-tag">' + (ConvertTo-HtmlSafe $art.category) + '</span><h3>' + (ConvertTo-HtmlSafe $art.title) + '</h3><p>' + (ConvertTo-HtmlSafe $art.excerpt) + '</p></div></a>'
        }) -join ''
        $relatedArticlesHtml = '<section class="ti-section reveal"><div class="ti-heading"><span class="ti-eyebrow">Plan with confidence</span><h2>Travel Insights</h2></div><div class="ti-grid">' + $riCards + '</div></section>'
    }

    # ---- Accordion items ----
    $accordionBlocks = New-Object System.Collections.Generic.List[string]
    $accordion = Get-PropertyValue $pc 'accordion' $null

    $guestConsiderations = @(Get-PropertyValue $accordion 'guest_considerations' @())
    if ($guestConsiderations.Count -gt 0) {
        $items = ($guestConsiderations | ForEach-Object { "<li>$_</li>" }) -join "`n"
        $accordionBlocks.Add('<div class="accordion-item"><button class="accordion-trigger"><span>Guest Considerations</span><b aria-hidden="true">&#8964;</b></button><div class="accordion-content"><ul class="accordion-list">' + $items + '</ul></div></div>')
    }
    $beforeYouArrive = @(Get-PropertyValue $accordion 'before_you_arrive' @())
    if ($beforeYouArrive.Count -gt 0) {
        $items = ($beforeYouArrive | ForEach-Object { "<li>$_</li>" }) -join "`n"
        $accordionBlocks.Add('<div class="accordion-item"><button class="accordion-trigger"><span>Before You Arrive</span><b aria-hidden="true">&#8964;</b></button><div class="accordion-content"><ul class="accordion-list">' + $items + '</ul></div></div>')
    }
    # Reservation Policy accordion: composed from the central policy file (core deposit/cancellation
    # wording + the no-show paragraph), never from a per-tour hard-coded copy. reservation_policy_extra
    # holds only what is genuinely tour-specific (date-change/weather/park-registration riders) --
    # see knowledge/policies/booking-cancellation.json's source_note for the full rationale.
    $includeNoshow = $true
    $noshowFlag = Get-PropertyValue $accordion 'reservation_policy_include_noshow' $null
    if ($null -ne $noshowFlag) { $includeNoshow = [bool]$noshowFlag }
    $reservationPolicy = @($policyCore)
    if ($includeNoshow) { $reservationPolicy += $policyNoshow }
    $reservationPolicy += @(Get-PropertyValue $accordion 'reservation_policy_extra' @())
    if ($reservationPolicy.Count -gt 0) {
        $items = ($reservationPolicy | ForEach-Object { "<p>$_</p>" }) -join "`n<hr>`n"
        $accordionBlocks.Add('<div class="accordion-item"><button class="accordion-trigger"><span>Reservation Policy</span><b aria-hidden="true">&#8964;</b></button><div class="accordion-content"><div class="accordion-policy">' + $items + '</div></div></div>')
    }
    $weatherPolicy = @(Get-PropertyValue $accordion 'weather_policy' @())
    if ($weatherPolicy.Count -gt 0) {
        $items = ($weatherPolicy | ForEach-Object { "<p>$_</p>" }) -join "`n<hr>`n"
        $accordionBlocks.Add('<div class="accordion-item"><button class="accordion-trigger"><span>Weather Policy</span><b aria-hidden="true">&#8964;</b></button><div class="accordion-content"><div class="accordion-policy">' + $items + '</div></div></div>')
    }
    $whatToPack = @(Get-PropertyValue $pc 'what_to_pack' @())
    if ($whatToPack.Count -gt 0) {
        $items = ($whatToPack | ForEach-Object { '<p><span class="check-red">&#10003;</span> ' + (ConvertTo-HtmlSafe $_) + '</p>' }) -join "`n"
        $accordionBlocks.Add('<div class="accordion-item"><button class="accordion-trigger"><span>What to Pack</span><b aria-hidden="true">&#8964;</b></button><div class="accordion-content"><div class="what-to-bring">' + $items + '</div></div></div>')
    }
    # "Everything Included" now renders as an always-visible block near the top
    # of the right column (after pricing), not buried in the accordion.
    $everythingIncluded = @(Get-PropertyValue $pc 'everything_included' @())
    $everythingIncludedTopHtml = ""
    if ($everythingIncluded.Count -gt 0) {
        $items = ($everythingIncluded | ForEach-Object { '<p><span class="check-red">&#10003;</span> ' + (ConvertTo-HtmlSafe $_) + '</p>' }) -join "`n"
        $everythingIncludedTopHtml = '<div class="everything-included-top reveal"><h3>Everything Included</h3><div class="itinerary-list">' + $items + '</div></div>'
    }
    $accordionHtml = $accordionBlocks -join "`n"

    # ---- Pricing ----
    $pricingTiers = Get-PropertyValue $pc 'pricing_tiers' $null
    $guideOnly = Get-PropertyValue $pricingTiers 'guide_only' $null
    $guideOnlyHtml = ""
    if ($guideOnly -and $guideOnly.price) {
        $guideOnlyHtml = '<div class="self-drive-price-card"><div><span class="pricing-eyebrow">Guide Only</span><h3>' + (ConvertTo-HtmlSafe $guideOnly.heading) + '</h3><p>' + (ConvertTo-HtmlSafe $guideOnly.description) + '</p></div><strong>From $' + [string]$guideOnly.price + '</strong></div>'
    }

    $options = @(Get-PropertyValue $pricingTiers 'options' @())
    $optionsCount = [Math]::Max(1, $options.Count)

    # Resolve each editorial option against tour-pricing.json via Tour Slug +
    # Option ID. An option with no option_id property is not yet migrated
    # and keeps its legacy rendering untouched (see header comment above).
    $tourPricingEntry = Get-PropertyValue $pricingData.tours $id $null
    $derivedOptions = $options | ForEach-Object {
        $opt = $_
        $optionId = [string](Get-PropertyValue $opt 'option_id' '')
        $estOpt = $null
        if ($optionId) {
            if (-not $tourPricingEntry) {
                throw "Tour '$id' option '$optionId': page_content declares an option_id but this tour has no entry at all in tour-pricing.json."
            }
            $estOpt = @($tourPricingEntry.options) | Where-Object { $_.id -eq $optionId } | Select-Object -First 1
            if (-not $estOpt) {
                throw "Tour '$id': page_content option_id '$optionId' has no matching entry in tour-pricing.json. Fix the Excel/Option ID mapping before regenerating."
            }
        }
        [pscustomobject]@{ editorial = $opt; optionId = $optionId; estOpt = $estOpt }
    }

    $optionsHtml = ($derivedOptions | ForEach-Object {
        $opt = $_.editorial
        $optionId = $_.optionId
        $estOpt = $_.estOpt
        $borderStyle = if ($options.Count -gt 1 -and $opt -eq $options[-1]) { ' style="border: 2px solid #062448;"' } else { '' }
        $headingTag = if ($opt.heading) { '<h3 style="font-size:.82rem; font-weight:700; color:#062448; margin-bottom:12px; line-height:1.4;">' + (ConvertTo-HtmlSafe $opt.heading) + '</h3>' } else { '' }

        if ($estOpt) {
            $priceInfo = Get-DerivedPriceInfo -EstOpt $estOpt -TourId $id -OptionId $optionId
            if ($priceInfo.isManualQuote) {
                $priceHtml = ''
            } else {
                $priceStr = Format-DerivedPrice $priceInfo.price
                $guestPhrase = Format-GuestPhrase $priceInfo.guestLabels
                $priceHtml = '<div class="tour-from-price"><span class="from-label">From</span> <strong class="from-amount">$' + $priceStr + ' <small>p.p.</small></strong></div><p class="tour-from-qualifier">for ' + $guestPhrase + '</p>'
                $priceValidationChecks.Add([pscustomobject]@{ slug = $slug; optionId = $optionId; expected = $priceStr }) | Out-Null
            }
            $noteHtml = '<p class="hiace-note"><span class="price-note">' + (ConvertTo-HtmlSafe (Get-PricingDisclaimer $priceInfo)) + '</span></p>'
            $dataAttr = ' data-option-id="' + (ConvertTo-HtmlSafe $optionId) + '"'
        } else {
            # Legacy path -- deprecated fields, unmigrated tour/option, unchanged from current production behavior.
            $priceHtml = if ($opt.price) { '<div class="tour-from-price"><span class="from-label">From</span> <strong class="from-amount">$' + [string]$opt.price + ' <small>p.p.</small></strong></div>' } else { '' }
            $noteHtml = if ($opt.note) { '<p class="hiace-note"><span class="price-note">' + (ConvertTo-HtmlSafe $opt.note) + '</span></p>' } else { '' }
            $dataAttr = ''
        }

        '<div class="tour-option-price-card"' + $borderStyle + $dataAttr + '><span class="option-badge">' + $opt.badge + '</span>' + $headingTag + $priceHtml + $noteHtml + '</div>'
    }) -join "`n"

    $bookingOptionsHtml = ($options | ForEach-Object { '<option>' + (ConvertTo-HtmlSafe $_.heading) + '</option>' }) -join "`n"
    if ($guideOnly -and $guideOnly.price) { $bookingOptionsHtml += "`n" + '<option>Guide Only &#8212; Self Drive</option>' }

    # ---- Price teaser (price + CTA surfaced early in the DOM, right after
    # Tour at a Glance, so mobile visitors and crawlers see it before the
    # long-form content) ----
    #
    # Derived-pricing path: once at least one option on this tour has been
    # migrated (has a resolved estOpt), the teaser shows the tour-wide
    # minimum derived price across every ACTIVE migrated option -- the same
    # Tour Slug + Option ID source as the cards below, never a separate
    # editorial field. A tour whose migrated options are all MANUAL QUOTE
    # gets the neutral "Private pricing available" message instead of a
    # number. Tours with no migrated options at all keep the legacy
    # price_confirmed-gated behavior, unchanged.
    $migratedOptions = @($derivedOptions | Where-Object { $_.estOpt })
    $priceTeaserHtml = ""
    # Reset every loop iteration -- $winner (below) is only assigned when
    # this tour has a migrated ACTIVE option; without this reset, a tour
    # with none (e.g. ostionalturtles, MANUAL QUOTE only) would silently
    # inherit the previous tour's $winner and leak its price into schema.
    $winner = $null
    if ($migratedOptions.Count -gt 0) {
        $activeMigrated = @($migratedOptions | Where-Object { $_.estOpt.estimator_status -eq 'active' })
        if ($activeMigrated.Count -gt 0) {
            $teaserCandidates = for ($teaserIdx = 0; $teaserIdx -lt $activeMigrated.Count; $teaserIdx++) {
                $candidateEntry = $activeMigrated[$teaserIdx]
                $pi = Get-DerivedPriceInfo -EstOpt $candidateEntry.estOpt -TourId $id -OptionId $candidateEntry.optionId
                [pscustomobject]@{ entry = $candidateEntry; priceInfo = $pi; sortOrder = $teaserIdx }
            }
            # Stable two-key sort: price ascending, then original option order ascending.
            # PowerShell's Sort-Object is not guaranteed stable on ties, so an explicit
            # secondary key is required to make Classic deterministically win a price tie
            # against Plus (Classic always appears first in page_content.pricing_tiers.options).
            $winner = $teaserCandidates | Sort-Object @{Expression={$_.priceInfo.price}}, @{Expression={$_.sortOrder}} | Select-Object -First 1
            $priceStr = Format-DerivedPrice $winner.priceInfo.price
            $guestPhrase = Format-GuestPhrase $winner.priceInfo.guestLabels
            $teaserBadge = $winner.entry.editorial.badge
            $priceTeaserHtml = '<div class="tour-price-teaser reveal" data-option-id="' + (ConvertTo-HtmlSafe $winner.entry.optionId) + '"><div class="container tour-price-teaser-inner"><span class="option-badge">' + $teaserBadge + '</span><div class="tour-from-price"><span class="from-label">From</span> <strong class="from-amount">$' + $priceStr + ' <small>p.p.</small></strong></div><p class="tour-from-qualifier">for ' + $guestPhrase + '</p><a class="btn btn-primary" href="#book">Check Availability &amp; Get My Private Quote</a></div></div>'
            $priceValidationChecks.Add([pscustomobject]@{ slug = $slug; optionId = $winner.entry.optionId; expected = $priceStr; isTeaser = $true }) | Out-Null

            # pricing.from_price staleness (informational): this field is no
            # longer read by schema Offer.price (see "Schema Offer.price"
            # below) or by recommendation-engine.ps1 (both now derive from
            # tour-pricing.json directly) -- its only remaining reader is
            # Start-Wild-CMS.ps1's editorial display. Flagged so an editor
            # knows to refresh it, but never blocks the build.
            if ($priceConfirmed -and $null -ne $canonicalFromPrice -and [double]$canonicalFromPrice -ne $winner.priceInfo.price) {
                $schemaPriceMismatches.Add("Tour '$id': pricing.from_price is `$$canonicalFromPrice but the tour-pricing.json-derived price is `$$($winner.priceInfo.price) (option '$($winner.entry.optionId)') -- update knowledge/tours/$id.json's pricing.from_price so the CMS editor doesn't show a stale value (public schema/recommendations already use the correct price).") | Out-Null
            }
        } else {
            $priceTeaserHtml = '<div class="tour-price-teaser reveal"><div class="container tour-price-teaser-inner"><span class="option-badge">PRIVATE TOUR</span><div class="tour-from-price"><strong class="from-amount" style="font-size:1.3rem;">Private pricing available</strong></div><a class="btn btn-primary" href="#book">Get Exact Quote</a></div></div>'
        }
    } elseif ($priceConfirmed -and $canonicalFromPrice) {
        # Legacy path -- unmigrated tour, unchanged from current production behavior.
        $primaryOptForBadge = $options | Where-Object { [bool](Get-PropertyValue $_ 'is_primary' $false) } | Select-Object -First 1
        $teaserBadge = if ($primaryOptForBadge) { $primaryOptForBadge.badge } elseif ($options.Count -gt 0) { $options[0].badge } else { 'PRIVATE TOUR' }
        $priceTeaserHtml = '<div class="tour-price-teaser reveal"><div class="container tour-price-teaser-inner"><span class="option-badge">' + $teaserBadge + '</span><div class="tour-from-price"><span class="from-label">From</span> <strong class="from-amount">$' + [string]$canonicalFromPrice + ' <small>p.p.</small></strong></div><a class="btn btn-primary" href="#book">Check Availability &amp; Get My Private Quote</a></div></div>'
    } elseif ($options.Count -gt 0 -or ($guideOnly -and $guideOnly.price)) {
        # No confirmed canonical price yet -- neutral conversion message
        # instead of implying a specific starting price.
        $priceTeaserHtml = '<div class="tour-price-teaser reveal"><div class="container tour-price-teaser-inner"><span class="option-badge">PRIVATE TOUR</span><div class="tour-from-price"><strong class="from-amount" style="font-size:1.3rem;">Private pricing available</strong></div><a class="btn btn-primary" href="#book">Get Exact Quote</a></div></div>'
    }

    # ---- Schema Offer.price ----
    # Migrated from pricing.from_price/page_content.pricing_tiers.options[].
    # is_primary to the exact same tour-pricing.json-derived minimum price
    # the public teaser above just used -- schema can no longer disagree
    # with the visible page by construction, not just by the guardrail
    # further below. Mirrors the teaser's own three cases exactly:
    #   1. A migrated ACTIVE option exists ($winner)      -> use its price.
    #   2. No migrated option, but a legacy confirmed price -> unchanged
    #      fallback behavior for an unmigrated tour (none exist today).
    #   3. Neither (e.g. ostionalturtles, MANUAL QUOTE only) -> omit
    #      offers.price entirely, same as before.
    $primaryOfferPrice = $null
    if ($winner) {
        $primaryOfferPrice = $winner.priceInfo.price
    } elseif ($priceConfirmed -and $canonicalFromPrice) {
        $primaryOfferPrice = $canonicalFromPrice
    }
    if ($primaryOfferPrice) {
        $touristTrip.offers = [ordered]@{"@type"="Offer";price=[string]$primaryOfferPrice;priceCurrency="USD";availability="https://schema.org/InStock"}
    }
    $schema = @{"@context"="https://schema.org";"@graph"=@($breadcrumb,$touristTrip)} | ConvertTo-Json -Depth 10 -Compress

    # Real per-tour departure time -- "To be confirmed" when not yet verified,
    # rather than a fixed placeholder time that's wrong for most tours.
    $departureTime = [string](Get-PropertyValue $pc 'departure_time' '')
    $departureOptionHtml = if ($departureTime) { '<option>' + (ConvertTo-HtmlSafe $departureTime) + '</option>' } else { '<option>To be confirmed</option>' }

    # ---- Quick stats ----
    $qs = Get-PropertyValue $pc 'quick_stats' $null
    $qsDifficulty = if ($qs -and $qs.difficulty) { [string]$qs.difficulty } else { [string]$tour.difficulty }
    $qsDuration = if ($qs -and $qs.duration) { [string]$qs.duration } else { [string]$tour.duration_label }
    $qsAvailability = if ($qs -and $qs.availability) { [string]$qs.availability } else { "Daily" }
    $bestFor = if ($qs -and $qs.best_for) { @($qs.best_for) } else { @(Get-PropertyValue $tour 'best_for' @()) }
    $qsBestForHtml = ($bestFor | ForEach-Object { '<span>' + (ConvertTo-HtmlSafe $_) + '</span>' }) -join "`n"

    # ---- Testimonials ----
    $testimonials = @(Get-PropertyValue $pc 'testimonials' @())
    $testimonialsSection = ""
    if ($testimonials.Count -gt 0) {
        $cards = ($testimonials | ForEach-Object {
            $initial = if ($_.author) { [string]$_.author.Substring(0,1) } else { "W" }
            $verifiedTag = if ($_.verified -eq $true) { '<span class="testimonial-verified">Shared with permission</span>' } else { '' }
            '<article class="testimonial-card reveal"><div class="testimonial-stars">&#9733;&#9733;&#9733;&#9733;&#9733;</div><blockquote>' + (ConvertTo-HtmlSafe $_.quote) + '</blockquote><div class="testimonial-author"><div class="rev-avatar">' + $initial + '</div><div><strong>' + (ConvertTo-HtmlSafe $_.author) + '</strong><span> &middot; ' + (ConvertTo-HtmlSafe $_.location) + '</span>' + $verifiedTag + '</div></div></article>'
        }) -join "`n"
        $testimonialsSection = '<section class="section testimonials-section" style="padding-top:48px;"><div class="container"><div class="section-head reveal"><span class="section-kicker">Traveler Stories</span><h2 class="section-title">Memories Made, Standards Exceeded</h2></div><div class="testimonials-grid">' + $cards + '</div></div></section>'
    }

    # ---- Cross-sell ----
    $crossSell = @(Get-PropertyValue $pc 'cross_sell' @())
    $crossSellSection = ""
    if ($crossSell.Count -gt 0) {
        $cards = ($crossSell | ForEach-Object {
            $img = [string]$_.image
            if (-not $img.StartsWith('..')) { $img = "../$img" }
            '<a href="' + $_.href + '" class="cross-sell-card"><img src="' + $img + '" alt="' + (ConvertTo-HtmlSafe $_.title) + '" class="cross-sell-img" loading="lazy" decoding="async"><div class="cross-sell-info"><div class="cross-sell-label">' + (ConvertTo-HtmlSafe $_.label) + '</div><div class="cross-sell-title">' + (ConvertTo-HtmlSafe $_.title) + '</div></div></a>'
        }) -join "`n"
        $crossSellSection = '<section class="cross-sell-section"><div class="container"><div class="section-head reveal"><span class="section-kicker">Keep Exploring</span><h2 class="section-title">You May Also Love</h2></div><div class="cross-sell-grid">' + $cards + '</div></div></section>'
    }

    # CRO pilot (Costa Rica Highlights only): a small, real Wild Papagayo
    # testimonial block placed near the decision point (right after the
    # FAQ, before the booking card). Reuses two verified quotes already
    # published on the homepage -- nothing invented. Every other tour gets
    # an empty string here, so __PILOT_REVIEWS__ renders as nothing for them.
    $pilotReviewsHtml = ''
    if ($id -eq 'costaricahighlights') {
        $pilotReviewsHtml = '<section class="section reviews-section"><div class="container"><div class="section-head reveal"><span class="section-kicker">Why travelers choose Wild Papagayo</span></div><div class="reviews-grid"><article class="review-card reveal"><div class="review-stars">&#9733;&#9733;&#9733;&#9733;&#9733;</div><blockquote>&quot;Our guide made the trip unforgettable. We felt like we had Costa Rica all to ourselves.&quot;</blockquote><cite>&mdash; Thomas B., Germany</cite></article><article class="review-card reveal"><div class="review-stars">&#9733;&#9733;&#9733;&#9733;&#9733;</div><blockquote>&quot;The most professional company we found in Costa Rica. Every detail was perfect.&quot;</blockquote><cite>&mdash; Sarah M., United States</cite></article></div></div></section>'
    }

    # ---- Assemble ----
    $html = $template
    $replacements = [ordered]@{
        '__SEO_TITLE__' = (ConvertTo-HtmlSafe $seoTitle)
        '__SEO_DESCRIPTION__' = (ConvertTo-HtmlSafe $seoDesc)
        '__CANONICAL__' = $canonical
        '__OG_TITLE__' = (ConvertTo-HtmlSafe $seoTitle)
        '__OG_DESCRIPTION__' = (ConvertTo-HtmlSafe $seoDesc)
        '__OG_IMAGE__' = $ogImage
        '__SCHEMA__' = $schema
        '__FAQ_SCHEMA__' = $faqSchemaTag
        '__WHY_PRIVATE_SECTION__' = $whyPrivateSection
        '__PRICE_TEASER__' = $priceTeaserHtml
        '__ITINERARY_STEPS__' = $itineraryHtml
        '__FAQ_SECTION__' = $faqHtml
        '__PILOT_REVIEWS__' = $pilotReviewsHtml
        '__RELATED_ARTICLES__' = $relatedArticlesHtml
        '__HERO_REGION__' = (ConvertTo-HtmlSafe $heroRegion)
        '__HERO_TITLE_HTML__' = $heroTitleHtml
        '__HERO_SUBTITLE__' = $heroSubtitleHtml
        '__HERO_CHIPS__' = $heroChipsHtml
        '__TOUR_GLANCE__' = $glanceHtml
        '__EVERYTHING_INCLUDED_TOP__' = $everythingIncludedTopHtml
        '__PEAK_SEASON_NOTE__' = $peakSeasonHtml
        '__PICKUP_AREAS__' = $pickupAreasHtml
        '__HERO_IMAGE__' = $heroImage
        '__HERO_IMAGE_ALT__' = (ConvertTo-HtmlSafe $heroImageAlt)
        '__HERO_IMAGE_DIM__' = $heroImageDim
        '__GALLERY_MAIN__' = $galleryMainHtml
        '__GALLERY_THUMBS__' = $galleryThumbsHtml
        '__TOUR_NAME__' = (ConvertTo-HtmlSafe $name)
        '__TOUR_SLUG__' = (ConvertTo-HtmlSafe $slug)
        '__EXPERIENCE_SECTION__' = $experienceSectionHtml
        '__ACCORDION_ITEMS__' = $accordionHtml
        '__DURATION_LABEL__' = (ConvertTo-HtmlSafe $qsDuration)
        '__SHORT_DESCRIPTION__' = (ConvertTo-HtmlSafe $shortDesc)
        '__PRICING_GUIDE_ONLY__' = $guideOnlyHtml
        '__OPTIONS_COUNT__' = [string]$optionsCount
        '__PRICING_OPTIONS__' = $optionsHtml
        '__QS_DIFFICULTY__' = (ConvertTo-HtmlSafe $qsDifficulty)
        '__QS_DURATION__' = (ConvertTo-HtmlSafe $qsDuration)
        '__QS_AVAILABILITY__' = (ConvertTo-HtmlSafe $qsAvailability)
        '__QS_BEST_FOR__' = $qsBestForHtml
        '__BOOKING_OPTIONS__' = $bookingOptionsHtml
        '__DEPARTURE_OPTION__' = $departureOptionHtml
        '__TESTIMONIALS_SECTION__' = $testimonialsSection
        '__CROSS_SELL_SECTION__' = $crossSellSection
    }
    foreach ($key in $replacements.Keys) {
        $html = $html.Replace($key, [string]$replacements[$key])
    }

    $outPath = Join-Path $outDir "$slug.html"
    Write-FileIfChanged -Path $outPath -Content $html
    $generated++
    Write-Host "Generated tour: tours/$slug.html" -ForegroundColor Green
}

Write-Host ""
Write-Host "Tour Engine complete: $generated page(s)." -ForegroundColor Cyan
if ($skipped.Count -gt 0) {
    Write-Host "Skipped:" -ForegroundColor Yellow
    $skipped | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

# ── Related Articles validation summary ──
Write-Host ""
Write-Host "== Related Articles (Travel Insights) ==" -ForegroundColor Cyan
$withArticles = @($tourRelatedStats | Where-Object { $_.entries.Count -gt 0 })
$withoutArticles = @($tourRelatedStats | Where-Object { $_.entries.Count -eq 0 })
$curatedCount = 0
$autoCount = 0
foreach ($stat in $tourRelatedStats) {
    foreach ($e in $stat.entries) {
        if ($e.reason -eq 'CURATED') { $curatedCount++ } else { $autoCount++ }
    }
}
Write-Host "Tours evaluated: $($tourRelatedStats.Count)"
Write-Host "Tours with related articles: $($withArticles.Count)"
Write-Host "Tours without related articles: $($withoutArticles.Count)"
Write-Host "Curated matches: $curatedCount"
Write-Host "Automatic tour_id matches: $autoCount"
Write-Host "Invalid related article slugs: $($invalidRelatedSlugs.Count)"
if ($invalidRelatedSlugs.Count -gt 0) {
    $invalidRelatedSlugs | ForEach-Object { Write-Host "  INVALID: tour='$($_.tour)' slug='$($_.slug)'" -ForegroundColor Red }
}
Write-Host ""
Write-Host "Tour -> Related Articles matrix:" -ForegroundColor Cyan
foreach ($stat in ($tourRelatedStats | Sort-Object tour)) {
    if ($stat.entries.Count -eq 0) { continue }
    Write-Host "  $($stat.tour)"
    $n = 0
    foreach ($e in $stat.entries) {
        $n++
        Write-Host "    #$n [$($e.reason)] $($e.article.slug) -- $($e.article.title)"
    }
}

# ── Derived public pricing validation ──
# For every price actually rendered from tour-pricing.json during this run,
# re-read the written HTML and confirm the exact dollar amount present next
# to that option's data-option-id matches what was computed. Looked up
# deterministically by slug + option_id, never by scanning for arbitrary "$"
# text on the page. A mismatch here means a future change reintroduced a
# stale/legacy value (or a formatting bug) and the build must not succeed.
Write-Host ""
Write-Host "== Derived Public Pricing Validation ==" -ForegroundColor Cyan
$pricingMismatches = New-Object System.Collections.Generic.List[object]
$checksBySlug = $priceValidationChecks | Group-Object slug
foreach ($group in $checksBySlug) {
    $slugForCheck = $group.Name
    $htmlPath = Join-Path $outDir "$slugForCheck.html"
    if (-not (Test-Path $htmlPath)) {
        $pricingMismatches.Add("Tour '$slugForCheck': expected generated file not found at $htmlPath") | Out-Null
        continue
    }
    $writtenHtml = [System.IO.File]::ReadAllText($htmlPath, [System.Text.Encoding]::UTF8)
    foreach ($check in $group.Group) {
        $isTeaser = [bool](Get-PropertyValue $check 'isTeaser' $false)
        $containerClass = if ($isTeaser) { 'tour-price-teaser' } else { 'tour-option-price-card' }
        $pattern = '<div class="' + [regex]::Escape($containerClass) + '(?:\s[^"]*)?"[^>]*data-option-id="' + [regex]::Escape($check.optionId) + '"[\s\S]{0,400}?from-amount">\$([\d,.]+)'
        $m = [regex]::Match($writtenHtml, $pattern)
        if (-not $m.Success) {
            $pricingMismatches.Add("Tour '$slugForCheck' option '$($check.optionId)' ($containerClass): could not find a rendered price to verify against expected `$$($check.expected)") | Out-Null
            continue
        }
        $actual = $m.Groups[1].Value.Replace(',', '')
        if ($actual -ne $check.expected) {
            $pricingMismatches.Add("Tour '$slugForCheck' option '$($check.optionId)' ($containerClass): expected `$$($check.expected) but HTML contains `$$actual") | Out-Null
        }
    }
}
Write-Host "Checks performed: $($priceValidationChecks.Count)"
if ($pricingMismatches.Count -gt 0) {
    Write-Host "MISMATCHES FOUND: $($pricingMismatches.Count)" -ForegroundColor Red
    $pricingMismatches | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "Derived public pricing validation failed -- refusing to leave a build with a price mismatch between tour-pricing.json and the generated HTML."
}
Write-Host "All derived prices verified against tour-pricing.json by Tour Slug + Option ID. 0 mismatches." -ForegroundColor Green

Write-Host ""
Write-Host "== pricing.from_price Staleness Check (editorial field, non-blocking) ==" -ForegroundColor Cyan
# Downgraded from a hard failure to a warning now that schema Offer.price
# and knowledge/recommendations.json are both migrated to read the
# tour-pricing.json-derived price directly (see tour-generator.ps1's
# "Schema Offer.price" section and recommendation-engine.ps1's
# Get-CanonicalTourFromPrice) -- pricing.from_price no longer drives any
# public output, so a stale value here is an editorial/CMS-display
# inconsistency, not a customer-facing price risk. A hard throw would
# block every build after every legitimate Excel price change until
# someone hand-edits 33 JSON files, defeating the point of having a
# single source of truth.
if ($schemaPriceMismatches.Count -gt 0) {
    Write-Host "$($schemaPriceMismatches.Count) tour(s) have a stale pricing.from_price (informational only):" -ForegroundColor Yellow
    $schemaPriceMismatches | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
} else {
    Write-Host "pricing.from_price matches tour-pricing.json for every price_confirmed tour. 0 stale values." -ForegroundColor Green
}

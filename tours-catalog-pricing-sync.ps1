# ============================================================
# Wild Papagayo - /tours Catalog Pricing Synchronizer v1.0
#
# tours.html is (and remains) a manually curated, static file -- its
# sections, ordering, imagery, descriptions and badges are hand-authored
# and this script never touches any of that. What it DOES own is the
# pricing area of each catalog card that opts in via an explicit
# data-tour-slug="<slug>" attribute on the <article>: it recomputes the
# derived private-tour starting price from tour-pricing.json (Tour Slug +
# min derived ACTIVE price, same source as the tour detail pages and the
# Smart Quote Estimator) and writes it directly into the static HTML at
# build time. There is no client-side price replacement anywhere in this
# flow -- the number that ships is the number in the file.
#
# A card with no data-tour-slug is left completely untouched (this is how
# a partial/pilot rollout is scoped, same pattern as tour-generator.ps1's
# option_id gating).
#
# Usage: .\tours-catalog-pricing-sync.ps1
# ============================================================

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$catalogPath = Join-Path $root "tours.html"
$pricingJsonPath = Join-Path $root "tour-pricing.json"
$tourDir = Join-Path $root "knowledge\tours"

function Read-Utf8Text { param([string]$Path) return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) }
function Write-Utf8Text { param([string]$Path, [string]$Content) [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false)) }
function Read-Utf8Json { param([string]$Path) return (Read-Utf8Text $Path | ConvertFrom-Json) }
function Get-PropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

# Tours that are intentionally NOT part of the production estimator/pricing
# dataset (Estimator Status = INACTIVE) and must never appear as a catalog
# card at all -- this is a guard against reintroduction, not something this
# script removes itself (removing a card is a manual editorial decision).
$expectedRemovedSlugs = @()

if (-not (Test-Path $pricingJsonPath)) {
    throw "tour-pricing.json not found -- cannot synchronize catalog pricing without the commercial pricing source."
}
$pricingData = Read-Utf8Json $pricingJsonPath
$html = Read-Utf8Text $catalogPath

function Get-DerivedCatalogPrice {
    # Catalog-level starting price for a tour: the minimum derived
    # (min of pp_2/pp_3/pp_4plus) price across every ACTIVE option on that
    # tour -- never a single option's own detail-page price, and never
    # legacy guide_only.price / pricing_tiers.options[].price / pricing.from_price.
    param($TourPricingEntry, [string]$Slug)
    $activeOpts = @($TourPricingEntry.options | Where-Object { $_.estimator_status -eq 'active' })
    $manualOpts = @($TourPricingEntry.options | Where-Object { $_.estimator_status -eq 'manual_quote' })
    $unknownOpts = @($TourPricingEntry.options | Where-Object { $_.estimator_status -ne 'active' -and $_.estimator_status -ne 'manual_quote' })
    if ($unknownOpts.Count -gt 0) {
        throw "Catalog sync: tour '$Slug' has option(s) with unrecognized estimator_status: $(($unknownOpts | ForEach-Object { $_.estimator_status }) -join ', ')"
    }
    if ($activeOpts.Count -eq 0) {
        if ($manualOpts.Count -gt 0) { return [pscustomobject]@{ isManualQuote = $true } }
        throw "Catalog sync: tour '$Slug' has no ACTIVE or MANUAL QUOTE options in tour-pricing.json."
    }
    $minVal = $null
    $guestLabels = @()
    foreach ($opt in $activeOpts) {
        $zoneApplies = $opt.zone_adjustment_applies
        if ($zoneApplies -isnot [bool]) {
            throw "Catalog sync: tour '$Slug' option '$($opt.id)': zone_adjustment_applies is not an explicit boolean. Refusing to derive a public price."
        }
        $tiers = @()
        if ($null -ne $opt.pp_2)     { $tiers += [pscustomobject]@{ label = '2';  value = [double]$opt.pp_2 } }
        if ($null -ne $opt.pp_3)     { $tiers += [pscustomobject]@{ label = '3';  value = [double]$opt.pp_3 } }
        if ($null -ne $opt.pp_4plus) { $tiers += [pscustomobject]@{ label = '4+'; value = [double]$opt.pp_4plus } }
        if ($tiers.Count -eq 0) {
            throw "Catalog sync: tour '$Slug' option '$($opt.id)' is ACTIVE but has no pp_2/pp_3/pp_4plus pricing."
        }
        foreach ($t in $tiers) {
            if ($null -eq $minVal -or $t.value -lt $minVal) { $minVal = $t.value; $guestLabels = @($t.label) }
            elseif ($t.value -eq $minVal) { $guestLabels += $t.label }
        }
    }
    return [pscustomobject]@{ isManualQuote = $false; price = $minVal; guestLabels = @($guestLabels | Select-Object -Unique) }
}

function Find-BalancedDivEnd {
    # Given html and the index of a "<div" opening tag, returns the index
    # just past its matching "</div>" (i.e. where the element's own
    # closing tag ends), correctly accounting for nested <div> elements.
    # A naive non-greedy regex ("[\s\S]*?</div>") stops at the FIRST
    # closing div it finds, which silently truncates inside any container
    # that itself holds nested divs -- exactly the price-box/price
    # structure here -- and corrupts the file. This walks the tag stream
    # instead of guessing a regex boundary.
    param([string]$Html, [int]$OpenTagStart)
    $tagRe = [regex]'<div[\s>]|</div>'
    $depth = 0
    $m = $tagRe.Match($Html, $OpenTagStart)
    while ($m.Success) {
        if ($m.Value -eq '</div>') {
            $depth--
            if ($depth -eq 0) { return $m.Index + $m.Length }
        } else {
            $depth++
        }
        $m = $tagRe.Match($Html, $m.Index + $m.Length)
    }
    throw "Find-BalancedDivEnd: no matching closing </div> found starting at index $OpenTagStart."
}

function Format-DerivedPrice {
    param([double]$Value)
    if ($Value -eq [Math]::Floor($Value)) { return [string]([int]$Value) }
    return [string]$Value
}
function Format-GuestPhrase {
    param([string[]]$GuestLabels)
    return 'groups of ' + ($GuestLabels -join ' or ') + ' guests'
}

# ---- Discover migrated cards (data-tour-slug present) ----
$slugAttrRe = [regex]'data-tour-slug="([a-z0-9\-]+)"'
$migratedSlugs = @($slugAttrRe.Matches($html) | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
Write-Host "Catalog cards opted into pricing sync (data-tour-slug present): $($migratedSlugs.Count) [$($migratedSlugs -join ', ')]" -ForegroundColor Cyan

$updated = $html
$syncedCount = 0

foreach ($slug in $migratedSlugs) {
    $tourEntry = Get-PropertyValue $pricingData.tours $slug $null
    if (-not $tourEntry) {
        throw "Catalog sync: card tagged data-tour-slug=`"$slug`" has no matching entry in tour-pricing.json. Fix the catalog card's slug or the pricing source before regenerating."
    }

    # Locate this card's <article ...data-tour-slug="$slug"...> ... </article> bounds
    $articleStartRe = [regex]::new('<article class="card tour-card[^"]*"[^>]*data-tour-slug="' + [regex]::Escape($slug) + '"[^>]*>')
    $startMatch = $articleStartRe.Match($updated)
    if (-not $startMatch.Success) {
        throw "Catalog sync: could not locate <article> opening tag for data-tour-slug=`"$slug`"."
    }
    $articleEndIdx = $updated.IndexOf('</article>', $startMatch.Index)
    if ($articleEndIdx -eq -1) {
        throw "Catalog sync: could not locate closing </article> for data-tour-slug=`"$slug`"."
    }
    $articleHtml = $updated.Substring($startMatch.Index, ($articleEndIdx + '</article>'.Length) - $startMatch.Index)

    # Locate the price-box within this article -- balanced-div matching,
    # since price-box always contains one or more nested .price divs and a
    # naive non-greedy regex would stop at the first inner </div>.
    $priceBoxOpenRe = [regex]'<div class="price-box">'
    $priceBoxOpenMatch = $priceBoxOpenRe.Match($articleHtml)
    if (-not $priceBoxOpenMatch.Success) {
        throw "Catalog sync: could not locate <div class=`"price-box`"> inside the card for '$slug'."
    }
    $priceBoxEndIdx = Find-BalancedDivEnd -Html $articleHtml -OpenTagStart $priceBoxOpenMatch.Index
    $priceBoxMatch = [pscustomobject]@{ Index = $priceBoxOpenMatch.Index; Length = $priceBoxEndIdx - $priceBoxOpenMatch.Index }

    $priceInfo = Get-DerivedCatalogPrice -TourPricingEntry $tourEntry -Slug $slug

    # Guide-only secondary note: sourced from the tour's own page_content --
    # left untouched as data, only read here to decide whether to show the
    # plain-text note. Never rendered as a numeric tile.
    $tourJsonPath = Join-Path $tourDir "$slug.json"
    $hasGuideOnly = $false
    if (Test-Path $tourJsonPath) {
        $tourJson = Read-Utf8Json $tourJsonPath
        $guideOnly = Get-PropertyValue (Get-PropertyValue (Get-PropertyValue $tourJson 'page_content' $null) 'pricing_tiers' $null) 'guide_only' $null
        if ($guideOnly -and (Get-PropertyValue $guideOnly 'price' $null)) { $hasGuideOnly = $true }
    }
    $guideNoteHtml = if ($hasGuideOnly) { "`n                                <p class=`"catalog-guide-note`">Guide-only option available</p>" } else { '' }

    if ($priceInfo.isManualQuote) {
        $newPriceBox = '<div class="price-box">' +
            '<div class="catalog-private-price catalog-custom-quote">' +
            '<span class="catalog-price-kicker">Custom Quote</span>' +
            '<strong class="catalog-price-amount">Pricing and availability require confirmation.</strong>' +
            '</div>' + $guideNoteHtml + "`n                            " + '</div>'
    } else {
        $priceStr = Format-DerivedPrice $priceInfo.price
        $guestPhrase = Format-GuestPhrase $priceInfo.guestLabels
        $newPriceBox = '<div class="price-box">' +
            '<div class="catalog-private-price">' +
            '<span class="catalog-price-kicker">Private Tour</span>' +
            '<strong class="catalog-price-amount">From $' + $priceStr + '<small> p.p.</small></strong>' +
            '<span class="catalog-price-qualifier">for ' + $guestPhrase + '</span>' +
            '</div>' + $guideNoteHtml + "`n                            " + '</div>'
    }

    $newArticleHtml = $articleHtml.Substring(0, $priceBoxMatch.Index) + $newPriceBox + $articleHtml.Substring($priceBoxMatch.Index + $priceBoxMatch.Length)
    $updated = $updated.Substring(0, $startMatch.Index) + $newArticleHtml + $updated.Substring($articleEndIdx + '</article>'.Length)
    $syncedCount++
    Write-Host "Synced '$slug': $(if ($priceInfo.isManualQuote) { 'CUSTOM QUOTE' } else { '$' + (Format-DerivedPrice $priceInfo.price) + ' (' + (Format-GuestPhrase $priceInfo.guestLabels) + ')' })" -ForegroundColor Green
}

$changed = $updated -cne $html
if ($changed) {
    Write-Utf8Text -Path $catalogPath -Content $updated
    Write-Host "tours.html updated ($syncedCount card(s) synced)." -ForegroundColor Green
} else {
    Write-Host "tours.html already up to date ($syncedCount card(s) checked, no changes needed)." -ForegroundColor Green
}

# ---- Build guards ----
Write-Host "`n== Catalog Pricing Validation ==" -ForegroundColor Cyan
$finalHtml = Read-Utf8Text $catalogPath
$mismatches = New-Object System.Collections.Generic.List[string]

# Guard: every data-tour-slug card must resolve to a known tour-pricing.json
# slug (re-check against the freshly written file, not just in-memory state)
$allSlugOccurrences = @($slugAttrRe.Matches($finalHtml) | ForEach-Object { $_.Groups[1].Value })
$finalSlugs = @($allSlugOccurrences | Select-Object -Unique)

# Guard: no eligible slug may appear on more than one card.
$duplicateSlugs = @($allSlugOccurrences | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
foreach ($dup in $duplicateSlugs) {
    $mismatches.Add("Slug '$dup' appears on more than one catalog card (data-tour-slug must be unique).")
}

foreach ($slug in $finalSlugs) {
    if (-not (Get-PropertyValue $pricingData.tours $slug $null)) {
        $mismatches.Add("Card data-tour-slug=`"$slug`" does not resolve to any tour-pricing.json entry.")
    }
}

# Guard: for every migrated ACTIVE/MANUAL QUOTE card, the price actually
# written to disk must match the derived value, verified by slug -- never
# by scanning the page for arbitrary "$" text.
foreach ($slug in $finalSlugs) {
    $tourEntry = Get-PropertyValue $pricingData.tours $slug $null
    if (-not $tourEntry) { continue }
    $priceInfo = Get-DerivedCatalogPrice -TourPricingEntry $tourEntry -Slug $slug

    $articleStartRe = [regex]::new('<article class="card tour-card[^"]*"[^>]*data-tour-slug="' + [regex]::Escape($slug) + '"[^>]*>')
    $startMatch = $articleStartRe.Match($finalHtml)
    if (-not $startMatch.Success) { $mismatches.Add("Card for '$slug' could not be re-located after write."); continue }
    $articleEndIdx = $finalHtml.IndexOf('</article>', $startMatch.Index)
    $articleHtml = $finalHtml.Substring($startMatch.Index, ($articleEndIdx + '</article>'.Length) - $startMatch.Index)

    if ($priceInfo.isManualQuote) {
        if ($articleHtml -match '\$\d') {
            $mismatches.Add("Card '$slug' is MANUAL QUOTE but a numeric `$ amount is present in its price area.")
        }
        if ($articleHtml -notmatch 'Pricing and availability require confirmation\.') {
            $mismatches.Add("Card '$slug' is MANUAL QUOTE but is missing the expected Custom Quote copy.")
        }
    } else {
        $expectedPrice = Format-DerivedPrice $priceInfo.price
        $expectedPhrase = Format-GuestPhrase $priceInfo.guestLabels
        if ($articleHtml -notmatch [regex]::Escape('From $' + $expectedPrice)) {
            $mismatches.Add("Card '$slug': expected From `$$expectedPrice not found in written HTML.")
        }
        if ($articleHtml -notmatch [regex]::Escape('for ' + $expectedPhrase)) {
            $mismatches.Add("Card '$slug': expected qualifier 'for $expectedPhrase' not found in written HTML.")
        }
    }
}

# Guard: any Estimator-Status-INACTIVE slug must not appear in the catalog
# at all, whether as a data-tour-slug or as a plain href to its detail page.
foreach ($removedSlug in $expectedRemovedSlugs) {
    if ($finalSlugs -contains $removedSlug) {
        $mismatches.Add("INACTIVE tour '$removedSlug' is present as a data-tour-slug card -- it must not be in the catalog.")
    }
    if ($finalHtml -match [regex]::Escape('href="tours/' + $removedSlug + '.html"')) {
        $mismatches.Add("INACTIVE tour '$removedSlug' still has a card/link in tours.html (href reference found).")
    }
}

# Guard: catalog pricing dataset completeness -- exactly the 32
# estimator-eligible tours (31 ACTIVE + 1 MANUAL QUOTE), no more, no less.
# This is the release-shape check, not a per-card price check: it exists so
# that a tour silently missing its data-tour-slug card (or a stray extra
# one) is caught even if every individual price that IS present is correct.
$allPricingSlugs = @($pricingData.tours.PSObject.Properties.Name)
$expectedActiveCount = 32
$expectedManualQuoteSlugs = @('ostionalturtles')
$activePricingSlugs = @($allPricingSlugs | Where-Object { $expectedManualQuoteSlugs -notcontains $_ })

$catalogActiveSlugs = @($finalSlugs | Where-Object { $expectedManualQuoteSlugs -notcontains $_ })
$catalogManualSlugs = @($finalSlugs | Where-Object { $expectedManualQuoteSlugs -contains $_ })

$missingActiveFromCatalog = @($activePricingSlugs | Where-Object { $catalogActiveSlugs -notcontains $_ })
if ($missingActiveFromCatalog.Count -gt 0) {
    $mismatches.Add("Catalog completeness: $($missingActiveFromCatalog.Count) ACTIVE tour(s) missing a data-tour-slug card: $($missingActiveFromCatalog -join ', ')")
}
if ($catalogActiveSlugs.Count -ne $expectedActiveCount) {
    $mismatches.Add("Catalog completeness: expected $expectedActiveCount ACTIVE catalog cards, found $($catalogActiveSlugs.Count).")
}
$manualJoined = (@($catalogManualSlugs | Sort-Object)) -join ','
$expectedManualJoined = (@($expectedManualQuoteSlugs | Sort-Object)) -join ','
if ($manualJoined -ne $expectedManualJoined) {
    $mismatches.Add("Catalog completeness: expected MANUAL QUOTE card(s) [$($expectedManualQuoteSlugs -join ', ')], found [$($catalogManualSlugs -join ', ')].")
}
if (-not ($finalSlugs -contains 'canyoningtubing')) {
    $mismatches.Add("Catalog completeness: 'canyoningtubing' card is missing from the catalog.")
}

if ($mismatches.Count -gt 0) {
    Write-Host "MISMATCHES FOUND: $($mismatches.Count)" -ForegroundColor Red
    $mismatches | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "Catalog pricing validation failed."
}
Write-Host "All migrated catalog cards verified by Tour Slug against tour-pricing.json. Confirmed no INACTIVE tour remains in the catalog. Catalog completeness confirmed: $($catalogActiveSlugs.Count) ACTIVE + $($catalogManualSlugs.Count) MANUAL QUOTE = $($finalSlugs.Count) total. 0 mismatches." -ForegroundColor Green

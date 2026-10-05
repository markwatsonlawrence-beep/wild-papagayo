# ============================================================
# Wild Papagayo - Experience Profile Engine v1.0
# Generates one landing page per real traveler profile already in
# the knowledge graph (couples, families, seniors, private,
# adventure, honeymoon, groups, first-time-visitors) at
# /profiles/<id>.html. Matches hotels/tours/destinations by
# word-overlap against their existing best_for tags (same
# technique as the Decision Engine block on blog articles);
# matches articles by their existing traveler_profile_ids. No
# new facts invented -- every card links to real, already-vetted
# content.
# ============================================================
$ErrorActionPreference = "Stop"

function Write-FileIfChanged {
    param([string]$Path, [string]$Content)
    if ((Test-Path $Path) -and ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) -ceq $Content)) { return }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}
$root = $PSScriptRoot
$templatePath = Join-Path $root "templates/profile.html"
$outputDir = Join-Path $root "profiles"
$siteUrl = "https://wildpapagayo.com"

if (-not (Test-Path $templatePath)) { throw "Missing template: $templatePath" }
New-Item -ItemType Directory -Force $outputDir | Out-Null

function Read-Utf8Json([string]$path) { return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }
function ConvertTo-HtmlSafe([object]$value) { return [System.Net.WebUtility]::HtmlEncode([string]$value) }
function Component([string]$name) {
    $p = Join-Path $root "templates/components/$name.html"
    if (-not (Test-Path $p)) { throw "Missing component: $p" }
    return [System.IO.File]::ReadAllText($p)
}
function Get-WildWordSet {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @(($Text.ToLowerInvariant() -split '[^a-z]+') | Where-Object { $_ })
}

$template = [System.IO.File]::ReadAllText($templatePath)
$header = Component "header"
$footer = Component "footer"
$ctaTemplate = Component "cta"
$heroImage = "images/luxury-costa-rica-tours-hero.webp"

$profiles = @(Read-Utf8Json (Join-Path $root 'knowledge\traveler-profiles.json'))

$hotels = @()
$hotelsDir = Join-Path $root 'knowledge\hotels'
if (Test-Path $hotelsDir) {
    $hotels = Get-ChildItem $hotelsDir -Filter '*.json' -File | ForEach-Object {
        $h = Read-Utf8Json $_.FullName
        # Strict publication gate: knowledge/hotels uses a flat top-level `status`;
        # only "published" may be recommended. Missing, "draft", "disabled" or
        # unknown => excluded (so an unfinished hotel with real scores cannot leak).
        if ([string]$h.status -ne 'published') { return }
        [pscustomobject]@{
            id = [string]$h.id
            name = [string]$h.name
            category = [string]$h.category
            best_for = @($h.best_for)
            scores = $h.hotel_scores
            hero_image = [string]$h.hero_image
            hero_image_alt = [string]$h.hero_image_alt
            description = [string]$h.hero_description
            # Temporary operational notice (e.g. a property closed for renovation) --
            # entirely source-driven and generic; absent on every hotel except one
            # currently carrying it, so every other card renders unaffected.
            operational_notice_card = if ($h.operational_notice -and $h.operational_notice.PSObject.Properties['card_message']) { [string]$h.operational_notice.card_message } else { '' }
        }
    }
}

$tours = @()
$toursDir = Join-Path $root 'knowledge\tours'
if (Test-Path $toursDir) {
    $tours = Get-ChildItem $toursDir -Filter '*.json' -File | ForEach-Object {
        $t = Read-Utf8Json $_.FullName
        [pscustomobject]@{
            id = [string]$t.id
            name = [string]$t.name
            category = [string]$t.category
            best_for = @($t.best_for)
            traveler_scores = $t.intelligence.traveler_scores
            image = [string]$t.hero_image
            description = [string]$t.short_description
            url = [string]$t.page_url
        }
    }
}

$destinations = @()
$destinationsDir = Join-Path $root 'knowledge\destinations'
if (Test-Path $destinationsDir) {
    $destinations = Get-ChildItem $destinationsDir -Filter '*.json' -File | ForEach-Object {
        $d = Read-Utf8Json $_.FullName
        # Explicit publication gate: only status "published" may be matched/linked.
        if ([string]$d.status -ne 'published') { return }
        [pscustomobject]@{
            id = [string]$d.id
            name = [string]$d.name
            best_for = @($d.best_for)
            scores = $d.experience_scores
            hero_image = [string]$d.hero_image
            description = [string]$d.hero_description
        }
    }
}

$blogPath = Join-Path $root 'blog-data.json'
$articles = if (Test-Path $blogPath) { @(Read-Utf8Json $blogPath) } else { @() }

$profileDescriptions = @{
    'couples'              = "Private tours, romantic settings and a pace built for two -- curated for couples exploring Guanacaste and Arenal together."
    'families'              = "Real family logistics matter: shorter transfers, easier trails, and hotels that work for kids and adults alike."
    'seniors'               = "Comfortable pacing, private transportation door to door, and experiences that don't demand extreme physical effort."
    'private'               = "The most exclusive resorts, private guides and elevated experiences Guanacaste and Arenal have to offer."
    'adventure'             = "Ziplines, volcanoes, whitewater and wildlife -- for travelers who want their Costa Rica trip to move."
    'honeymoon'             = "Private, romantic and unhurried -- experiences and stays built for a first trip together as a married couple."
    'groups'                = "Private transportation and experiences sized for friends or extended family traveling together."
    'first-time-visitors'   = "New to Costa Rica? Start here -- the logistics, hotels and tours that make a first trip smooth."
}

$generated = 0
foreach ($profile in $profiles) {
    $profileId = [string]$profile.id
    $profileName = [string]$profile.name
    $profileWords = Get-WildWordSet ($profileId -replace '-', ' ')
    $canonical = "$siteUrl/profiles/$profileId"

    function Test-WordMatch($itemBestFor, $profileWords) {
        foreach ($bf in $itemBestFor) {
            $bfWords = Get-WildWordSet $bf
            foreach ($pw in $profileWords) {
                # Prefix match in both directions -- catches plurals/stems
                # ("honeymoon" vs "Honeymoons", "senior" vs "Seniors").
                foreach ($bw in $bfWords) {
                    if ($bw.StartsWith($pw) -or $pw.StartsWith($bw)) { return $true }
                }
            }
        }
        return $false
    }

    # Prefer the precise, already-computed numeric scores (tour intelligence.traveler_scores
    # 0-100, hotel/destination experience_scores 1-5) over fuzzy best_for text matching --
    # only fall back to word-overlap when an entity has no score for this profile at all.
    # "adventure" profile maps to the tour/hotel field "adventure_access".
    $scoreKeyAliases = @{ adventure = @('adventure', 'adventure_access') }
    $scoreKeys = if ($scoreKeyAliases.ContainsKey($profileId)) { $scoreKeyAliases[$profileId] } else { @($profileId) }

    function Get-EntityScore($item, $scoreKeys) {
        if (-not $item.scores) { return $null }
        foreach ($key in $scoreKeys) {
            $prop = $item.scores.PSObject.Properties[$key]
            if ($prop) {
                $val = $prop.Value
                if ($val -is [double] -or $val -is [int]) { return [double]$val }
                if ($val.PSObject.Properties['score']) { return [double]$val.score }
            }
        }
        return $null
    }
    function Get-TourScore($item, $scoreKeys) {
        if (-not $item.traveler_scores) { return $null }
        foreach ($key in $scoreKeys) {
            $prop = $item.traveler_scores.PSObject.Properties[$key]
            if ($prop) { return [double]$prop.Value }
        }
        return $null
    }
    # Optional per-profile curated render order. Most profiles have no preferred_* field, so this
    # is a no-op everywhere except where a profile explicitly opts in (currently honeymoon only) --
    # eligibility (best_for/score matching) is unchanged; this only controls which 3 eligible items
    # are shown first. Preferred IDs that are no longer eligible are skipped; remaining slots fall
    # back to the normal score/word-match selection, excluding items already shown.
    function Get-TopMatches($items, $scoreFn, $scoreKeys, $profileWords, $preferredIds = @()) {
        $scored = @($items | ForEach-Object { [pscustomobject]@{ item = $_; score = (& $scoreFn $_ $scoreKeys) } })
        $withScore = @($scored | Where-Object { $null -ne $_.score })
        $eligibleIds = if ($withScore.Count -gt 0) {
            @($withScore | ForEach-Object { $_.item.id })
        } else {
            @($items | Where-Object { Test-WordMatch $_.best_for $profileWords } | ForEach-Object { $_.id })
        }

        $prioritized = @()
        if ($preferredIds -and @($preferredIds).Count -gt 0) {
            foreach ($preferredId in @($preferredIds)) {
                if ($eligibleIds -contains $preferredId) {
                    $match = $items | Where-Object { $_.id -eq $preferredId } | Select-Object -First 1
                    if ($match) { $prioritized += $match }
                }
            }
        }
        if ($prioritized.Count -ge 3) { return @($prioritized | Select-Object -First 3) }

        $usedIds = @($prioritized | ForEach-Object { $_.id })
        $remainingSlots = 3 - $prioritized.Count
        $fallback = if ($withScore.Count -gt 0) {
            @($withScore | Where-Object { $usedIds -notcontains $_.item.id } | Sort-Object score -Descending | Select-Object -First $remainingSlots | ForEach-Object { $_.item })
        } else {
            @($items | Where-Object { ($usedIds -notcontains $_.id) -and (Test-WordMatch $_.best_for $profileWords) } | Select-Object -First $remainingSlots)
        }
        return @($prioritized + $fallback)
    }

    $preferredTourIds = if ($profile.PSObject.Properties['preferred_tours']) { @($profile.preferred_tours) } else { @() }
    $preferredDestinationIds = if ($profile.PSObject.Properties['preferred_destinations']) { @($profile.preferred_destinations) } else { @() }

    $matchedHotels = Get-TopMatches $hotels ${function:Get-EntityScore} $scoreKeys $profileWords
    $matchedTours = Get-TopMatches $tours ${function:Get-TourScore} $scoreKeys $profileWords $preferredTourIds
    $matchedDestinations = Get-TopMatches $destinations ${function:Get-EntityScore} $scoreKeys $profileWords $preferredDestinationIds
    $matchedArticles = @($articles | Where-Object { @($_.traveler_profile_ids) -contains $profileId } | Select-Object -First 3)

    $hotelCards = @($matchedHotels | ForEach-Object {
        $noticeHtml = if ($_.operational_notice_card) { "<p style=`"color:#9a6b1f;font-size:12px;font-weight:700;margin:-6px 0 12px`">$(ConvertTo-HtmlSafe $_.operational_notice_card)</p>" } else { '' }
        "<a class=`"wp-destination-experience-card`" href=`"../hotels/$($_.id)`"><img class=`"wp-destination-experience-image`" src=`"../$($_.hero_image)`" alt=`"$(ConvertTo-HtmlSafe $_.hero_image_alt)`" loading=`"lazy`" decoding=`"async`"><div class=`"wp-destination-experience-content`"><span class=`"wp-destination-experience-label`">$(ConvertTo-HtmlSafe $_.category)</span><h3>$(ConvertTo-HtmlSafe $_.name)</h3><p>$(ConvertTo-HtmlSafe $_.description)</p>$noticeHtml<span class=`"wp-destination-experience-link`">View Hotel &rarr;</span></div></a>"
    })
    if ($hotelCards.Count -eq 0) { $hotelCards = @("<p>Hotel matches for $(ConvertTo-HtmlSafe $profileName) are coming soon.</p>") }

    $tourCards = @($matchedTours | ForEach-Object {
        "<a class=`"wp-destination-experience-card`" href=`"$($_.url)`"><img class=`"wp-destination-experience-image`" src=`"../$($_.image)`" alt=`"$(ConvertTo-HtmlSafe $_.name)`" loading=`"lazy`" decoding=`"async`"><div class=`"wp-destination-experience-content`"><span class=`"wp-destination-experience-label`">$(ConvertTo-HtmlSafe $_.category)</span><h3>$(ConvertTo-HtmlSafe $_.name)</h3><p>$(ConvertTo-HtmlSafe $_.description)</p><span class=`"wp-destination-experience-link`">View Experience &rarr;</span></div></a>"
    })
    if ($tourCards.Count -eq 0) { $tourCards = @("<p>Tour matches for $(ConvertTo-HtmlSafe $profileName) are coming soon.</p>") }

    $destCards = @($matchedDestinations | ForEach-Object {
        "<a class=`"wp-destination-experience-card`" href=`"../destinations/$($_.id)`"><img class=`"wp-destination-experience-image`" src=`"../$($_.hero_image)`" alt=`"$(ConvertTo-HtmlSafe $_.name)`" loading=`"lazy`" decoding=`"async`"><div class=`"wp-destination-experience-content`"><span class=`"wp-destination-experience-label`">Destination</span><h3>$(ConvertTo-HtmlSafe $_.name)</h3><p>$(ConvertTo-HtmlSafe $_.description)</p><span class=`"wp-destination-experience-link`">Explore &rarr;</span></div></a>"
    })
    if ($destCards.Count -eq 0) { $destCards = @("<p>Destination matches for $(ConvertTo-HtmlSafe $profileName) are coming soon.</p>") }

    $articleCards = @($matchedArticles | ForEach-Object {
        $img = if ($_.image_top -and (Test-Path (Join-Path $root $_.image_top))) { $_.image_top } else { $heroImage }
        "<a class=`"wp-destination-experience-card`" href=`"../blog/$($_.slug)`"><img class=`"wp-destination-experience-image`" src=`"../$img`" alt=`"$(ConvertTo-HtmlSafe $_.image_top_alt)`" loading=`"lazy`" decoding=`"async`"><div class=`"wp-destination-experience-content`"><span class=`"wp-destination-experience-label`">$(ConvertTo-HtmlSafe $_.category)</span><h3>$(ConvertTo-HtmlSafe $_.title)</h3><p>$(ConvertTo-HtmlSafe $_.excerpt)</p><span class=`"wp-destination-experience-link`">Read Article &rarr;</span></div></a>"
    })
    if ($articleCards.Count -eq 0) { $articleCards = @("<a class=`"wp-destination-experience-card`" href=`"../Blogs`"><div class=`"wp-destination-experience-content`"><span class=`"wp-destination-experience-label`">Insider Guide</span><h3>Explore our Travel Blog</h3><p>Real traveler questions about Costa Rica, answered by the local team.</p><span class=`"wp-destination-experience-link`">Read Articles &rarr;</span></div></a>") }

    # Optional per-profile narrative block (currently honeymoon only). Absent/blank on every other
    # profile => __NARRATIVE_SECTION__ resolves to "", so those 7 outputs are unaffected byte-for-byte.
    $narrativeHtml = if ($profile.PSObject.Properties['narrative_html'] -and [string]$profile.narrative_html) {
        "<section class=`"destination-section destination-section--narrative`">$([string]$profile.narrative_html)</section>"
    } else { "" }

    $profileDescription = if ($profileDescriptions.ContainsKey($profileId)) { $profileDescriptions[$profileId] } else { "Curated hotels, tours and destinations for $($profileName.ToLowerInvariant())." }
    $cta = $ctaTemplate.Replace('__DESTINATION_NAME__', $profileName).Replace('__CTA_URL__', "https://wa.me/50688566325?text=$([Uri]::EscapeDataString("Hello Wild Papagayo! I'm planning a trip as $($profileName.ToLowerInvariant()) and would love local help."))")
    $schemaObj = [ordered]@{'@context'='https://schema.org';'@type'='CollectionPage';name="$profileName in Guanacaste & Arenal";description=$profileDescription;url=$canonical}
    $schema = $schemaObj | ConvertTo-Json -Compress

    $html = $template.Replace('__COMPONENT_HEADER__', $header).Replace('__COMPONENT_FOOTER__', $footer).Replace('__COMPONENT_CTA__', $cta)
    $replacements = @{
        '__SEO_TITLE__'           = "$profileName Guide to Guanacaste & Arenal | Wild Papagayo"
        '__SEO_DESCRIPTION__'     = $profileDescription
        '__CANONICAL__'           = $canonical
        '__SCHEMA__'              = $schema
        '__HERO_IMAGE__'          = $heroImage
        '__PROFILE_NAME__'        = $profileName
        '__PROFILE_DESCRIPTION__' = $profileDescription
        '__NARRATIVE_SECTION__'   = $narrativeHtml
        '__HOTEL_CARDS__'         = ($hotelCards -join "`n")
        '__TOUR_CARDS__'          = ($tourCards -join "`n")
        '__DESTINATION_CARDS__'   = ($destCards -join "`n")
        '__ARTICLE_CARDS__'       = ($articleCards -join "`n")
    }
    foreach ($key in $replacements.Keys) { $html = $html.Replace($key, $replacements[$key]) }
    $out = Join-Path $outputDir "$profileId.html"
    Write-FileIfChanged -Path $out -Content $html
    Write-Host "Generated profile: profiles/$profileId.html"
    $generated++
}
Write-Host "Experience Profile Engine complete: $generated page(s)."

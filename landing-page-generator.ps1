# ============================================================
# Wild Papagayo - Private Tours Landing Page Engine v1.0
# Generates commercial "hub" landing pages (e.g. Private Tours
# from Peninsula Papagayo) from knowledge/landing-pages/*.json,
# using templates/landing-page.html. Config-driven so the same
# structure can be reused for future hotel-specific landings
# (Four Seasons, Andaz, Nekajui, ...) without duplicating code.
# ============================================================
$ErrorActionPreference = "Stop"

function Write-FileIfChanged {
    param([string]$Path, [string]$Content)
    if ((Test-Path $Path) -and ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) -ceq $Content)) { return }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}
$root = $PSScriptRoot
$siteUrl = "https://wildpapagayo.com"

function Read-Utf8Json([string]$path) { return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }
function ConvertTo-HtmlSafe([object]$value) { return [System.Net.WebUtility]::HtmlEncode([string]$value) }
function Get-PropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}
function Component([string]$name) {
    $p = Join-Path $root "templates/components/$name.html"
    if (-not (Test-Path $p)) { throw "Missing component: $p" }
    return [System.IO.File]::ReadAllText($p)
}

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

$templatePath = Join-Path $root "templates/landing-page.html"
$configDir = Join-Path $root "knowledge/landing-pages"
if (-not (Test-Path $templatePath)) { throw "Missing template: $templatePath" }
if (-not (Test-Path $configDir)) { throw "Missing config dir: $configDir" }

$template = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)
$header = Component "header"
$footer = Component "footer"

# ---- Load tours & hotels for lookups ----
$toursDir = Join-Path $root "knowledge/tours"
$tourById = @{}
if (Test-Path $toursDir) {
    Get-ChildItem $toursDir -Filter "*.json" -File | ForEach-Object {
        $t = Read-Utf8Json $_.FullName
        $tourById[[string]$t.id] = $t
    }
}
$hotelsDir = Join-Path $root "knowledge/hotels"
$hotelById = @{}
if (Test-Path $hotelsDir) {
    Get-ChildItem $hotelsDir -Filter "*.json" -File | ForEach-Object {
        $h = Read-Utf8Json $_.FullName
        $hotelById[[string]$h.id] = $h
    }
}

$configFiles = Get-ChildItem $configDir -Filter "*.json" -File

# ---- Hotel -> landing page lookup (so pickup cards on hub/activity pages
# can link straight to a hotel-specific landing when one exists, instead of
# the generic hotel guide page) ----
$landingByHotelId = @{}
$configFiles | ForEach-Object {
    $cfg = Read-Utf8Json $_.FullName
    $hid = [string](Get-PropertyValue $cfg 'hotel_id' '')
    if ($hid) { $landingByHotelId[$hid] = [string]$cfg.slug }
}
$count = 0
foreach ($file in $configFiles) {
    $c = Read-Utf8Json $file.FullName
    $canonical = [string]$c.canonical_url
    $ctaIntent = [string](Get-PropertyValue $c 'cta_intent' 'book_tour')
    $outDirName = [string](Get-PropertyValue $c 'output_dir' 'private-tours')
    $outDir = Join-Path $root $outDirName
    New-Item -ItemType Directory -Force $outDir | Out-Null

    # ---- Hero ----
    $hero = $c.hero
    $heroCtaSecondaryUrl = "https://wa.me/50688566325?text=" + [Uri]::EscapeDataString([string]$hero.cta_secondary_whatsapp)
    $heroSection = '<header class="plp-hero"><div class="plp-hero-inner">' +
        '<div class="plp-hero-eyebrow"><span>' + (ConvertTo-HtmlSafe $hero.eyebrow_line_1) + '</span><span>' + (ConvertTo-HtmlSafe $hero.eyebrow_line_2) + '</span></div>' +
        '<h1>' + (ConvertTo-HtmlSafe $c.h1) + '</h1>' +
        '<p class="plp-hero-sub">' + (ConvertTo-HtmlSafe $hero.subtext) + '</p>' +
        '<div class="plp-hero-actions">' +
        '<a class="btn btn-primary" data-intent="' + (ConvertTo-HtmlSafe $ctaIntent) + '" data-cta-location="' + (ConvertTo-HtmlSafe $c.id) + '_hero" href="' + (ConvertTo-HtmlSafe $hero.cta_primary_url) + '">' + (ConvertTo-HtmlSafe $hero.cta_primary_text) + '</a>' +
        '<a class="btn btn-secondary" style="border-color:#fff;color:#fff;" data-intent="' + (ConvertTo-HtmlSafe $ctaIntent) + '" data-cta-location="' + (ConvertTo-HtmlSafe $c.id) + '_hero" href="' + (ConvertTo-HtmlSafe $heroCtaSecondaryUrl) + '" target="_blank" rel="noopener noreferrer">' + (ConvertTo-HtmlSafe $hero.cta_secondary_text) + '</a>' +
        '</div></div>' +
        '<div class="plp-hero-photo"><img src="../' + (ConvertTo-HtmlSafe $hero.image) + '" alt="' + (ConvertTo-HtmlSafe $c.h1) + '"' + (Get-ImageDimAttrs $hero.image) + ' loading="eager" fetchpriority="high" decoding="async"></div>' +
        '</header>'

    # ---- Trust strip ----
    $trustStrip = (@($c.trust_strip) | ForEach-Object { '<div class="plp-trust-item">' + (ConvertTo-HtmlSafe $_) + '</div>' }) -join ''

    # ---- Intro section ----
    $intro = $c.intro_section
    $introParas = (@($intro.paragraphs) | ForEach-Object { '<p>' + (ConvertTo-HtmlSafe $_) + '</p>' }) -join ''
    $introSection = '<section class="plp-section plp-section-narrow"><div class="container"><span class="section-kicker">' + (ConvertTo-HtmlSafe $intro.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $intro.title) + '</h2>' + $introParas + '</div></section>'

    # ---- Featured tours ----
    $ft = $c.featured_tours
    $tourCards = (@($ft.tours) | ForEach-Object {
        $tid = [string]$_.id
        if (-not $tourById.ContainsKey($tid)) { return }
        $t = $tourById[$tid]
        $url = [string]$t.page_url
        $img = [string]$t.hero_image
        '<a class="plp-tour-card" href="../' + (ConvertTo-HtmlSafe $url.TrimStart('.','/')) + '"><div class="plp-tour-img"><img src="../' + (ConvertTo-HtmlSafe $img) + '" alt="' + (ConvertTo-HtmlSafe $t.name) + '"' + (Get-ImageDimAttrs $img) + ' loading="lazy" decoding="async"></div><div class="plp-tour-body"><span class="plp-tour-best">' + (ConvertTo-HtmlSafe $_.best_for) + '</span><h3>' + (ConvertTo-HtmlSafe $t.name) + '</h3><p>' + (ConvertTo-HtmlSafe $_.note) + '</p><span class="plp-tour-link">View Experience &rarr;</span></div></a>'
    }) -join ''
    $featuredToursHtml = '<div class="section-head" style="text-align:center;"><span class="section-kicker">' + (ConvertTo-HtmlSafe $ft.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $ft.title) + '</h2></div><div class="plp-tour-grid">' + $tourCards + '</div>'
    $ftCta = Get-PropertyValue $ft 'cta' $null
    if ($ftCta) {
        $featuredToursHtml += '<div style="text-align:center;margin-top:32px;"><a class="btn btn-secondary" href="../' + (ConvertTo-HtmlSafe ([string]$ftCta.url).TrimStart('.','/')) + '">' + (ConvertTo-HtmlSafe $ftCta.text) + ' &rarr;</a></div>'
    }
    $featuredToursSectionHtml = '<section class="plp-section" id="featured-tours"><div class="container">' + $featuredToursHtml + '</div></section>'

    # ---- Experience comparison (optional, reusable) -- a table comparing
    # several real tours side by side. Difficulty and duration are always
    # pulled live from the tour's own master data, never hand-typed in the
    # landing config, so the table can't drift out of sync with the product. ----
    $experienceComparisonHtml = ""
    $ec = Get-PropertyValue $c 'experience_comparison' $null
    if ($ec) {
        $ecRows = (@($ec.tours) | ForEach-Object {
            $tid = [string]$_.tour_id
            if (-not $tourById.ContainsKey($tid)) { return }
            $t = $tourById[$tid]
            $url = '../' + ([string]$t.page_url).TrimStart('.','/')
            $diff = [string](Get-PropertyValue $t 'difficulty' '')
            $dur = [string](Get-PropertyValue $t 'duration_label' '')
            '<tr><td><a href="' + (ConvertTo-HtmlSafe $url) + '">' + (ConvertTo-HtmlSafe $t.name) + '</a></td><td>' + (ConvertTo-HtmlSafe $_.best_for) + '</td><td>' + (ConvertTo-HtmlSafe $diff) + '</td><td>' + (ConvertTo-HtmlSafe $dur) + '</td><td>' + (ConvertTo-HtmlSafe $_.highlights) + '</td></tr>'
        }) -join ''
        $ecIntroText = [string](Get-PropertyValue $ec 'intro_text' '')
        $ecIntroHtml = if ($ecIntroText) { '<p style="color:#4a5568;font-size:1rem;max-width:760px;margin:16px auto 0;text-align:center;">' + (ConvertTo-HtmlSafe $ecIntroText) + '</p>' } else { '' }
        $ecBody = '<div class="section-head" style="text-align:center;"><span class="section-kicker">' + (ConvertTo-HtmlSafe $ec.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $ec.title) + '</h2>' + $ecIntroHtml + '</div><div style="overflow-x:auto;"><table class="plp-table"><thead><tr><th>Experience</th><th>Best For</th><th>Activity Level</th><th>Duration</th><th>Highlights</th></tr></thead><tbody>' + $ecRows + '</tbody></table></div>'
        $experienceComparisonHtml = '<section class="plp-section"><div class="container">' + $ecBody + '</div></section>'
    }

    # ---- About section (optional) -- a plain kicker/title/text block with a
    # single CTA, reused for any "explain the destination/experience" content
    # that needs its own H2 outside the intro (e.g. "Why Visit Rio Celeste?"). ----
    $aboutSectionHtml = ""
    $about = Get-PropertyValue $c 'about_section' $null
    if ($about) {
        $aboutBody = '<span class="section-kicker">' + (ConvertTo-HtmlSafe $about.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $about.title) + '</h2><p>' + (ConvertTo-HtmlSafe $about.text) + '</p>'
        $aboutCta = Get-PropertyValue $about 'cta' $null
        if ($aboutCta) {
            $aboutCtaUrl = [string]$aboutCta.url
            $aboutCtaIsExternal = $aboutCtaUrl.StartsWith('http')
            $aboutCtaUrl = if ($aboutCtaIsExternal) { $aboutCtaUrl } else { '../' + $aboutCtaUrl }
            $aboutCtaAttrs = if ($aboutCtaIsExternal) { ' target="_blank" rel="noopener noreferrer"' } else { '' }
            $aboutBody += '<a class="btn btn-secondary" href="' + (ConvertTo-HtmlSafe $aboutCtaUrl) + '"' + $aboutCtaAttrs + '>' + (ConvertTo-HtmlSafe $aboutCta.text) + ' &rarr;</a>'
        }
        $aboutSectionHtml = '<section class="plp-section plp-section-alt plp-section-narrow"><div class="container">' + $aboutBody + '</div></section>'
    }

    # ---- Decision blocks (optional, reusable, named) -- a generic "compare
    # two or more angles" component: a kicker/title/intro plus N side-by-side
    # columns (each a short list or paragraph) and an optional CTA. Used for
    # "should I combine X with Y", "who is this trip for", or any other
    # pros/cons or planning-tips content. Config supplies a dictionary keyed
    # by a short name (e.g. "who_for"), referenced from section_order as
    # "DECISION_BLOCK:who_for" so several distinct blocks can be placed at
    # different points in the page instead of always rendering together. ----
    $decisionBlocksMap = [ordered]@{}
    $db = Get-PropertyValue $c 'decision_blocks' $null
    if ($db) {
        foreach ($prop in $db.PSObject.Properties) {
            $block = $prop.Value
            $cols = (@($block.columns) | ForEach-Object {
                $items = @(Get-PropertyValue $_ 'items' @())
                $colBody = if ($items.Count -gt 0) {
                    '<ul>' + (($items | ForEach-Object { '<li>' + (ConvertTo-HtmlSafe $_) + '</li>' }) -join '') + '</ul>'
                } else {
                    '<p>' + (ConvertTo-HtmlSafe (Get-PropertyValue $_ 'text' '')) + '</p>'
                }
                '<div class="plp-decision-col"><h3>' + (ConvertTo-HtmlSafe $_.title) + '</h3>' + $colBody + '</div>'
            }) -join ''
            $dbIntro = [string](Get-PropertyValue $block 'intro' '')
            $dbIntroHtml = if ($dbIntro) { '<p style="color:#4a5568;font-size:1rem;max-width:700px;margin:16px auto 0;">' + (ConvertTo-HtmlSafe $dbIntro) + '</p>' } else { '' }
            $dbBody = '<div class="section-head" style="text-align:center;"><span class="section-kicker">' + (ConvertTo-HtmlSafe $block.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $block.title) + '</h2>' + $dbIntroHtml + '</div><div class="plp-decision-grid">' + $cols + '</div>'
            $dbCta = Get-PropertyValue $block 'cta' $null
            if ($dbCta) {
                $dbCtaUrl = [string]$dbCta.url
                $dbCtaUrl = if ($dbCtaUrl.StartsWith('http')) { $dbCtaUrl } else { '../' + $dbCtaUrl }
                $dbBody += '<div style="text-align:center;margin-top:28px;"><a class="btn btn-primary" href="' + (ConvertTo-HtmlSafe $dbCtaUrl) + '">' + (ConvertTo-HtmlSafe $dbCta.text) + ' &rarr;</a></div>'
            }
            $decisionBlocksMap[$prop.Name] = '<section class="plp-section"><div class="container">' + $dbBody + '</div></section>'
        }
    }

    # ---- Content blocks (optional, reusable, named) -- a plain-HTML text
    # section for pages that must state their facts in crawlable markup
    # (e.g. a transfer route): kicker/title plus any of paragraphs, an ordered
    # "steps" list, a bulleted "items" list, a label/value "facts" table and an
    # optional CTA. Config supplies a dictionary keyed by a short name,
    # referenced from section_order as "CONTENT_BLOCK:name". Renders nothing
    # unless a page's config declares "content_blocks", so existing pages are
    # unaffected. ----
    $contentBlocksMap = [ordered]@{}
    $cbs = Get-PropertyValue $c 'content_blocks' $null
    if ($cbs) {
        foreach ($prop in $cbs.PSObject.Properties) {
            $blk = $prop.Value
            $cbKicker = [string](Get-PropertyValue $blk 'kicker' '')
            $cbBody = ''
            if ($cbKicker) { $cbBody += '<span class="section-kicker">' + (ConvertTo-HtmlSafe $cbKicker) + '</span>' }
            $cbBody += '<h2 class="section-title" style="margin-bottom:16px;">' + (ConvertTo-HtmlSafe $blk.title) + '</h2>'
            $cbBody += ((@(Get-PropertyValue $blk 'paragraphs' @()) | ForEach-Object { '<p style="color:#4a5568;font-size:1rem;line-height:1.75;margin:0 0 16px;">' + (ConvertTo-HtmlSafe $_) + '</p>' }) -join '')
            $cbFacts = @(Get-PropertyValue $blk 'facts' @())
            if ($cbFacts.Count -gt 0) {
                $factRows = ($cbFacts | ForEach-Object { '<tr><td style="width:30%;font-weight:700;color:#062448;vertical-align:top;text-align:left;">' + (ConvertTo-HtmlSafe $_.label) + '</td><td style="text-align:left;">' + (ConvertTo-HtmlSafe $_.value) + '</td></tr>' }) -join ''
                $cbBody += '<div style="overflow-x:auto;"><table class="plp-table plp-facts"><tbody>' + $factRows + '</tbody></table></div>'
            }
            $cbSteps = @(Get-PropertyValue $blk 'steps' @())
            if ($cbSteps.Count -gt 0) {
                $cbBody += '<ol style="margin:16px 0 0;padding-left:22px;line-height:1.7;color:#4a5568;">' + (($cbSteps | ForEach-Object { '<li style="margin-bottom:8px;">' + (ConvertTo-HtmlSafe $_) + '</li>' }) -join '') + '</ol>'
            }
            $cbItems = @(Get-PropertyValue $blk 'items' @())
            if ($cbItems.Count -gt 0) {
                $cbBody += '<ul class="plp-simple-list">' + (($cbItems | ForEach-Object { '<li>' + (ConvertTo-HtmlSafe $_) + '</li>' }) -join '') + '</ul>'
            }
            $cbCta = Get-PropertyValue $blk 'cta' $null
            if ($cbCta) {
                $cbCtaUrl = [string]$cbCta.url
                $cbIsExternal = $cbCtaUrl.StartsWith('http')
                $cbCtaUrl = if ($cbIsExternal) { $cbCtaUrl } else { '../' + $cbCtaUrl }
                $cbCtaAttrs = if ($cbIsExternal) { ' target="_blank" rel="noopener noreferrer"' } else { '' }
                $cbBody += '<p style="margin-top:20px;"><a class="btn btn-secondary" href="' + (ConvertTo-HtmlSafe $cbCtaUrl) + '"' + $cbCtaAttrs + '>' + (ConvertTo-HtmlSafe $cbCta.text) + ' &rarr;</a></p>'
            }
            $cbAlt = if ([bool](Get-PropertyValue $blk 'alt' $false)) { ' plp-section-alt' } else { '' }
            $contentBlocksMap[$prop.Name] = '<section class="plp-section' + $cbAlt + '"><div class="container"><div style="max-width:820px;margin:0 auto;text-align:left;">' + $cbBody + '</div></div></section>'
        }
    }

    # ---- Tour selector table(s) -- reusable "if you want X, recommended
    # experience is Y" table. Most pages have one; some (e.g. a hotel page
    # that also has a "one free day" shortcut) have a second with its own
    # kicker/title, via the optional "secondary_selector" key. ----
    function Build-SelectorTable($ts) {
        $rows = (@($ts.rows) | ForEach-Object {
            $tid = [string]$_.tour_id
            $t = if ($tourById.ContainsKey($tid)) { $tourById[$tid] } else { $null }
            $name = if ($t) { [string]$t.name } else { $tid }
            $url = if ($t) { '../' + ([string]$t.page_url).TrimStart('.','/') } else { '#' }
            '<tr><td>' + (ConvertTo-HtmlSafe $_.want) + '</td><td><a href="' + (ConvertTo-HtmlSafe $url) + '">' + (ConvertTo-HtmlSafe $name) + '</a></td></tr>'
        }) -join ''
        $wantHeader = [string](Get-PropertyValue $ts 'want_header' 'If You Want...')
        $body = '<div class="section-head" style="text-align:center;"><span class="section-kicker">' + (ConvertTo-HtmlSafe $ts.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $ts.title) + '</h2></div><div style="overflow-x:auto;"><table class="plp-table"><thead><tr><th>' + (ConvertTo-HtmlSafe $wantHeader) + '</th><th>Recommended Experience</th></tr></thead><tbody>' + $rows + '</tbody></table></div>'
        $ctaObj = Get-PropertyValue $ts 'cta' $null
        if ($ctaObj) { $body += '<div style="text-align:center;margin-top:24px;"><a class="btn btn-primary" href="' + (ConvertTo-HtmlSafe $ctaObj.whatsapp_url) + '" target="_blank" rel="noopener noreferrer">' + (ConvertTo-HtmlSafe $ctaObj.text) + '</a></div>' }
        return $body
    }
    $tourSelector = Get-PropertyValue $c 'tour_selector' $null
    $tourSelectorHtml = if ($tourSelector) { '<section class="plp-section plp-section-alt"><div class="container">' + (Build-SelectorTable $tourSelector) + '</div></section>' } else { '' }
    $secondarySelector = Get-PropertyValue $c 'secondary_selector' $null
    $secondarySelectorHtml = if ($secondarySelector) { '<section class="plp-section"><div class="container">' + (Build-SelectorTable $secondarySelector) + '</div></section>' } else { '' }

    # ---- Curated journeys (optional -- a more editorial alternative to the
    # comparison-table selectors, for premium/concierge-toned pages. Cards
    # can link to a real tour, or omit a link entirely for a concierge-style
    # "custom day" card that ends in a WhatsApp CTA instead. ----
    $curatedJourneysHtml = ""
    $cj = Get-PropertyValue $c 'curated_journeys' $null
    if ($cj) {
        $cards = (@($cj.journeys) | ForEach-Object {
            $tid = [string](Get-PropertyValue $_ 'tour_id' '')
            $linkHtml = ""
            if ($tid -and $tourById.ContainsKey($tid)) {
                $t = $tourById[$tid]
                $url = '../' + ([string]$t.page_url).TrimStart('.','/')
                $linkHtml = '<a href="' + (ConvertTo-HtmlSafe $url) + '">View Experience &rarr;</a>'
            } elseif (Get-PropertyValue $_ 'whatsapp_url' '') {
                $linkHtml = '<a href="' + (ConvertTo-HtmlSafe $_.whatsapp_url) + '" target="_blank" rel="noopener noreferrer">' + (ConvertTo-HtmlSafe (Get-PropertyValue $_ 'link_text' 'Talk to a Local Expert')) + ' &rarr;</a>'
            }
            '<div class="plp-journey-card"><h3>' + (ConvertTo-HtmlSafe $_.title) + '</h3><p>' + (ConvertTo-HtmlSafe $_.text) + '</p>' + $linkHtml + '</div>'
        }) -join ''
        $curatedJourneysHtml = '<section class="plp-section plp-section-alt"><div class="container"><div class="section-head" style="text-align:center;"><span class="section-kicker">' + (ConvertTo-HtmlSafe $cj.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $cj.title) + '</h2></div><div class="plp-journeys-grid">' + $cards + '</div>'
        $customCta = Get-PropertyValue $cj 'custom_cta' $null
        if ($customCta) {
            $customWaUrl = "https://wa.me/50688566325?text=" + [Uri]::EscapeDataString([string]$customCta.whatsapp_message)
            $curatedJourneysHtml += '<div class="plp-custom-block"><h2>' + (ConvertTo-HtmlSafe $customCta.title) + '</h2><p>' + (ConvertTo-HtmlSafe $customCta.text) + '</p><a class="btn btn-primary" data-intent="book_tour" data-cta-location="' + (ConvertTo-HtmlSafe $c.id) + '_custom" href="' + (ConvertTo-HtmlSafe $customWaUrl) + '" target="_blank" rel="noopener noreferrer">' + (ConvertTo-HtmlSafe $customCta.cta_text) + '</a></div>'
        }
        $curatedJourneysHtml += '</div></section>'
    }

    # ---- Pickup section: either a multi-hotel "resort_pickups" grid (hub
    # pages) or a single-hotel "hotel_pickup" blurb (hotel-specific child
    # pages) -- whichever is present in this page's config. ----
    $pickupSectionHtml = ""
    $rp = Get-PropertyValue $c 'resort_pickups' $null
    if ($rp) {
        function Build-PickupGroup($group) {
            $cards = (@($group.hotels) | ForEach-Object {
                $hid = [string]$_.id
                if (-not $hotelById.ContainsKey($hid)) { return }
                $h = $hotelById[$hid]
                $img = [string]$h.hero_image
                $href = if ($landingByHotelId.ContainsKey($hid)) { '../private-tours/' + $landingByHotelId[$hid] } else { '../hotels/' + $hid }
                '<a class="plp-pickup-card" href="' + (ConvertTo-HtmlSafe $href) + '"><div class="plp-pickup-img"><img src="../' + (ConvertTo-HtmlSafe $img) + '" alt="' + (ConvertTo-HtmlSafe $h.name) + '"' + (Get-ImageDimAttrs $img) + ' loading="lazy" decoding="async"></div><div class="plp-pickup-card-body"><h4>' + (ConvertTo-HtmlSafe $h.name) + '</h4><span>' + (ConvertTo-HtmlSafe $_.cta) + ' &rarr;</span></div></a>'
            }) -join ''
            return '<div class="plp-pickup-group"><span class="plp-pickup-label">' + (ConvertTo-HtmlSafe $group.label) + '</span><div class="plp-pickup-grid">' + $cards + '</div></div>'
        }
        $resortPickupsHtml = '<div class="section-head" style="text-align:center;"><span class="section-kicker">' + (ConvertTo-HtmlSafe $rp.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $rp.title) + '</h2><p style="color:#4a5568;font-size:1rem;max-width:700px;margin:16px auto 0;">' + (ConvertTo-HtmlSafe $rp.intro) + '</p></div>' + (Build-PickupGroup $rp.inside_peninsula) + (Build-PickupGroup $rp.nearby)
        $pickupSectionHtml = '<section class="plp-section"><div class="container">' + $resortPickupsHtml + '</div></section>'
    } else {
        $hp = Get-PropertyValue $c 'hotel_pickup' $null
        if ($hp) {
            $hpBody = '<span class="section-kicker">' + (ConvertTo-HtmlSafe $hp.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $hp.title) + '</h2><p>' + (ConvertTo-HtmlSafe $hp.text) + '</p>'
            if ($hp.text_2) { $hpBody += '<p>' + (ConvertTo-HtmlSafe $hp.text_2) + '</p>' }
            $hpBody += '<a class="btn btn-primary" data-intent="' + (ConvertTo-HtmlSafe $ctaIntent) + '" data-cta-location="' + (ConvertTo-HtmlSafe $c.id) + '_pickup" href="' + (ConvertTo-HtmlSafe $hp.cta_url) + '" target="_blank" rel="noopener noreferrer">' + (ConvertTo-HtmlSafe $hp.cta_text) + '</a>'
            $pickupSectionHtml = '<section class="plp-section plp-section-alt"><div class="container plp-single-pickup">' + $hpBody + '</div></section>'
        }
    }

    # ---- Travel times ----
    $tt = $c.travel_times
    $ttOriginLabel = [string](Get-PropertyValue $tt 'origin_label' 'Papagayo')
    $ttRows = (@($tt.rows) | ForEach-Object {
        '<tr><td>' + (ConvertTo-HtmlSafe $_.destination) + '</td><td>' + [string]$_.min + '&ndash;' + [string]$_.max + ' min</td><td>' + (ConvertTo-HtmlSafe $_.best_for) + '</td></tr>'
    }) -join ''
    $travelTimesHtml = '<div class="section-head" style="text-align:center;"><span class="section-kicker">' + (ConvertTo-HtmlSafe $tt.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $tt.title) + '</h2></div><div style="overflow-x:auto;"><table class="plp-table"><thead><tr><th>Destination</th><th>Approx. Travel Time from ' + (ConvertTo-HtmlSafe $ttOriginLabel) + '</th><th>Best For</th></tr></thead><tbody>' + $ttRows + '</tbody></table></div><p class="plp-table-note">' + (ConvertTo-HtmlSafe $tt.note) + ' (' + (ConvertTo-HtmlSafe $tt.source_note) + ')</p>'
    $travelTimesSectionHtml = '<section class="plp-section plp-section-alt"><div class="container">' + $travelTimesHtml + '</div></section>'

    # ---- Traveler types (optional -- hub pages use the generic 5-card grid;
    # hotel-specific child pages typically replace this with richer
    # audience_sections instead) ----
    $travelerTypesHtml = ""
    $tty = Get-PropertyValue $c 'traveler_types' $null
    if ($tty) {
        $ttyCards = (@($tty.types) | ForEach-Object { '<div class="plp-traveler-card"><h3>' + (ConvertTo-HtmlSafe $_.title) + '</h3><p>' + (ConvertTo-HtmlSafe $_.text) + '</p></div>' }) -join ''
        $travelerTypesHtml = '<section class="plp-section"><div class="container"><div class="section-head" style="text-align:center;"><span class="section-kicker">' + (ConvertTo-HtmlSafe $tty.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $tty.title) + '</h2></div><div class="plp-traveler-grid">' + $ttyCards + '</div></div></section>'
    }

    # ---- Audience sections (optional, one or more rich blocks -- e.g.
    # separate "Four Seasons Families" and "Couples" sections on a
    # hotel-specific child page) ----
    $audienceSectionsHtml = ""
    $audienceSections = @(Get-PropertyValue $c 'audience_sections' @())
    if ($audienceSections.Count -gt 0) {
        $blocks = ($audienceSections | ForEach-Object {
            $sec = $_
            $groupCards = (@($sec.groups) | ForEach-Object { '<div class="plp-audience-card"><h3>' + (ConvertTo-HtmlSafe $_.title) + '</h3><p>' + (ConvertTo-HtmlSafe $_.text) + '</p></div>' }) -join ''
            $introHtml = if ($sec.intro) { '<p style="color:#4a5568;font-size:1rem;max-width:760px;margin:16px auto 0;">' + (ConvertTo-HtmlSafe $sec.intro) + '</p>' } else { '' }
            '<div class="plp-audience-section"><div class="section-head" style="text-align:center;"><span class="section-kicker">' + (ConvertTo-HtmlSafe $sec.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $sec.title) + '</h2>' + $introHtml + '</div><div class="plp-audience-groups">' + $groupCards + '</div></div>'
        }) -join '<div style="height:44px;"></div>'
        $audienceSectionsHtml = '<section class="plp-section plp-section-alt"><div class="container">' + $blocks + '</div></section>'
    }

    # ---- Why private ----
    $wp = $c.why_private
    $wpItems = (@($wp.items) | ForEach-Object { '<div class="why-private-item reveal"><h3>' + (ConvertTo-HtmlSafe $_.title) + '</h3><p>' + (ConvertTo-HtmlSafe $_.text) + '</p></div>' }) -join ''
    $whyPrivateHtml = '<div class="section-head reveal" style="text-align:center;"><span class="section-kicker">' + (ConvertTo-HtmlSafe $wp.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $wp.title) + '</h2></div><div class="why-private-grid">' + $wpItems + '</div><div class="plp-tagline"><strong>' + (ConvertTo-HtmlSafe $wp.tagline) + '</strong><span>' + (ConvertTo-HtmlSafe $wp.tagline_text) + '</span></div>'
    $whyPrivateSectionHtml = '<section class="plp-section plp-section-alt why-private-section"><div class="container">' + $whyPrivateHtml + '</div></section>'

    # ---- Expectations (optional, reusable) -- a "don't overpromise" wildlife
    # section: a guarantee-free framing plus an honest "what else you might
    # see" list, meant for activity-intent pages built around an animal or
    # natural phenomenon. ----
    $expectationsHtml = ""
    $exp = Get-PropertyValue $c 'expectations' $null
    if ($exp) {
        $expBody = '<span class="section-kicker">' + (ConvertTo-HtmlSafe $exp.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $exp.title) + '</h2><p>' + (ConvertTo-HtmlSafe $exp.text) + '</p>'
        $alsoSee = @(Get-PropertyValue $exp 'also_see' @())
        if ($alsoSee.Count -gt 0) {
            $alsoSeeItems = ($alsoSee | ForEach-Object { '<li>' + (ConvertTo-HtmlSafe $_) + '</li>' }) -join ''
            $expBody += '<h3 class="plp-subhead">' + (ConvertTo-HtmlSafe (Get-PropertyValue $exp 'also_see_title' 'What Else Might You See?')) + '</h3><ul class="plp-simple-list">' + $alsoSeeItems + '</ul>'
        }
        $expectationsHtml = '<section class="plp-section plp-section-alt plp-section-narrow"><div class="container">' + $expBody + '</div></section>'
    }

    # ---- Families section (optional, reusable) -- a short suitability note
    # for activity-intent pages, distinct from the richer traveler_types /
    # audience_sections grids used on hotel pages. ----
    $familiesSectionHtml = ""
    $fam = Get-PropertyValue $c 'families_section' $null
    if ($fam) {
        $famParas = (@($fam.paragraphs) | ForEach-Object { '<p>' + (ConvertTo-HtmlSafe $_) + '</p>' }) -join ''
        $famBody = '<span class="section-kicker">' + (ConvertTo-HtmlSafe $fam.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $fam.title) + '</h2>' + $famParas
        $familiesSectionHtml = '<section class="plp-section plp-section-narrow"><div class="container">' + $famBody + '</div></section>'
    }

    # ---- Editorial crosslink (optional) -- points to a related blog/guide
    # article so a commercial landing and an editorial article on the same
    # topic reinforce each other instead of competing for the same query. ----
    $editorialCrosslinkHtml = ""
    $edc = Get-PropertyValue $c 'editorial_crosslink' $null
    if ($edc) {
        $edcBody = '<span class="section-kicker">' + (ConvertTo-HtmlSafe $edc.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $edc.title) + '</h2><p>' + (ConvertTo-HtmlSafe $edc.text) + '</p><a class="btn btn-secondary" href="../' + (ConvertTo-HtmlSafe $edc.cta_url) + '">' + (ConvertTo-HtmlSafe $edc.cta_text) + ' &rarr;</a>'
        $editorialCrosslinkHtml = '<section class="plp-section plp-section-narrow"><div class="container plp-crosslink">' + $edcBody + '</div></section>'
    }

    # ---- Airport section (optional -- hotel-intent pages typically include
    # it, activity-intent pages may skip it) ----
    $airportSectionHtml = ""
    $air = Get-PropertyValue $c 'airport_section' $null
    if ($air) {
        $airportHtml = '<span class="section-kicker">' + (ConvertTo-HtmlSafe $air.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $air.title) + '</h2><p>' + (ConvertTo-HtmlSafe $air.text) + '</p><a class="btn btn-secondary" href="../' + (ConvertTo-HtmlSafe $air.cta_url) + '">' + (ConvertTo-HtmlSafe $air.cta_text) + ' &rarr;</a>'
        $airportSectionHtml = '<section class="plp-section plp-section-narrow"><div class="container">' + $airportHtml + '</div></section>'
    }

    # ---- Hotel crosslink (optional -- child pages link back to their own
    # hotel guide; hub pages omit this entirely) ----
    $hotelCrosslinkHtml = ""
    $hc = Get-PropertyValue $c 'hotel_crosslink' $null
    if ($hc) {
        $hcBody = '<span class="section-kicker">' + (ConvertTo-HtmlSafe $hc.kicker) + '</span><h2 class="section-title">' + (ConvertTo-HtmlSafe $hc.title) + '</h2><p>' + (ConvertTo-HtmlSafe $hc.text) + '</p><a class="btn btn-secondary" href="../' + (ConvertTo-HtmlSafe $hc.cta_url) + '">' + (ConvertTo-HtmlSafe $hc.cta_text) + ' &rarr;</a>'
        $hotelCrosslinkHtml = '<section class="plp-section plp-section-narrow"><div class="container plp-crosslink">' + $hcBody + '</div></section>'
    }

    # ---- Parent hub link (optional -- child pages point back up to their
    # parent hub landing, e.g. Four Seasons -> Peninsula Papagayo) and/or
    # child landing links (optional -- hub pages point down to their
    # hotel-specific children as those get built) ----
    $parentHubLinkHtml = ""
    $hub = Get-PropertyValue $c 'parent_hub' $null
    if ($hub) {
        $parentHubLinkHtml = '<div class="plp-hub-link">Part of our <a href="../' + (ConvertTo-HtmlSafe $hub.url) + '">' + (ConvertTo-HtmlSafe $hub.title) + '</a> guide</div>'
    }
    $childLandings = @(Get-PropertyValue $c 'child_landings' @())
    if ($childLandings.Count -gt 0) {
        $childLinks = ($childLandings | ForEach-Object { '<a href="../' + (ConvertTo-HtmlSafe $_.url) + '">' + (ConvertTo-HtmlSafe $_.title) + '</a>' }) -join ' &middot; '
        $parentHubLinkHtml = '<div class="plp-hub-link">Hotel-specific guides: ' + $childLinks + '</div>'
    }
    # ---- Child landing groups (optional) -- like child_landings above, but
    # split into labeled rows (e.g. "Hotel-specific guides" vs "Experience
    # guides") once a hub has more than one axis of child page. Takes
    # priority over the flat child_landings key when both are present. ----
    $childLandingGroups = @(Get-PropertyValue $c 'child_landing_groups' @())
    if ($childLandingGroups.Count -gt 0) {
        $groupRows = ($childLandingGroups | ForEach-Object {
            $links = (@($_.items) | ForEach-Object { '<a href="../' + (ConvertTo-HtmlSafe $_.url) + '">' + (ConvertTo-HtmlSafe $_.title) + '</a>' }) -join ' &middot; '
            '<div class="plp-hub-link">' + (ConvertTo-HtmlSafe $_.label) + ': ' + $links + '</div>'
        }) -join ''
        $parentHubLinkHtml = $groupRows
    }

    # ---- FAQ + schema ----
    $faqBlocks = (@($c.faq) | ForEach-Object { '<div class="tours-faq-item"><h3>' + (ConvertTo-HtmlSafe $_.q) + '</h3><p>' + (ConvertTo-HtmlSafe $_.a) + '</p></div>' }) -join ''
    $faqSectionHtml = '<div class="section-head" style="text-align:center;"><span class="section-kicker">Questions</span><h2 class="section-title">Frequently Asked Questions</h2></div><div style="margin-top:20px;max-width:820px;margin-left:auto;margin-right:auto;">' + $faqBlocks + '</div>'
    $faqSectionWrapped = '<section class="plp-section plp-section-alt"><div class="container">' + $faqSectionHtml + '</div></section>'
    $faqEntities = @(@($c.faq) | ForEach-Object { @{ '@type'='Question'; name=[string]$_.q; acceptedAnswer=@{ '@type'='Answer'; text=[string]$_.a } } })

    # ---- Final CTA ----
    $fc = $c.final_cta
    $fcWaUrl = "https://wa.me/50688566325?text=" + [Uri]::EscapeDataString([string]$fc.whatsapp_message)
    $finalCtaHtml = '<section class="plp-final-cta"><div class="container"><p class="kicker">' + (ConvertTo-HtmlSafe $fc.kicker) + '</p><h2>' + (ConvertTo-HtmlSafe $fc.title) + '</h2><p class="body">' + (ConvertTo-HtmlSafe $fc.text) + '</p><div class="plp-final-actions">' +
        '<a class="btn btn-primary" data-intent="' + (ConvertTo-HtmlSafe $ctaIntent) + '" data-cta-location="' + (ConvertTo-HtmlSafe $c.id) + '_final" href="' + (ConvertTo-HtmlSafe $fcWaUrl) + '" target="_blank" rel="noopener noreferrer">' + (ConvertTo-HtmlSafe $fc.cta_primary_text) + '</a>' +
        '<a class="btn btn-secondary" data-intent="' + (ConvertTo-HtmlSafe $ctaIntent) + '" data-cta-location="' + (ConvertTo-HtmlSafe $c.id) + '_final" href="' + (ConvertTo-HtmlSafe $fcWaUrl) + '" target="_blank" rel="noopener noreferrer">' + (ConvertTo-HtmlSafe $fc.cta_secondary_text) + '</a>' +
        '</div></div></section>'

    # ---- Schema (BreadcrumbList + WebPage) ----
    $bc = Get-PropertyValue $c 'breadcrumb_parent' $null
    $bcName = if ($bc) { [string]$bc.name } else { 'Private Tours' }
    $bcUrl = if ($bc) { "$siteUrl/" + ([string]$bc.url).TrimStart('/') } else { "$siteUrl/tours" }
    # Links this page (not a hotel entity -- Wild Papagayo doesn't operate
    # the hotel, it provides transportation to/from it) to the single
    # site-wide Wild Papagayo organization node, same @id and pattern used
    # by hotel-generator.ps1/tour-generator.ps1/destination-generator.ps1 --
    # deliberately not a second, conflicting declaration of the entity.
    # Opt-in via config (include_organization_schema) rather than applied to
    # every landing page this generator serves, so this fix stays scoped to
    # the specific pages it was authorized for (Phase 11) instead of
    # silently changing the other landing pages sharing this generator.
    # Optional stable node id (config "webpage_id": true) -- "<canonical>#webpage"
    # -- so other nodes/pages can reference this page; omitted by default so
    # existing landing pages keep their exact current output.
    $webPageEntity = [ordered]@{ '@type'='WebPage' }
    if ([bool](Get-PropertyValue $c 'webpage_id' $false)) { $webPageEntity['@id'] = "$canonical#webpage" }
    $webPageEntity['name'] = [string]$c.seo_title
    $webPageEntity['description'] = [string]$c.seo_description
    $webPageEntity['url'] = $canonical
    if ([bool](Get-PropertyValue $c 'include_organization_schema' $false)) {
        $webPageEntity['publisher'] = [ordered]@{ '@type'='TravelAgency'; '@id'="$siteUrl/#organization"; name='Wild Papagayo' }
    }
    $schemaGraph = @(
        $webPageEntity,
        [ordered]@{ '@type'='BreadcrumbList'; itemListElement=@(
            [ordered]@{ '@type'='ListItem'; position=1; name='Home'; item="$siteUrl/" },
            [ordered]@{ '@type'='ListItem'; position=2; name=$bcName; item=$bcUrl },
            [ordered]@{ '@type'='ListItem'; position=3; name=[string]$c.h1; item=$canonical }
        )},
        [ordered]@{ '@type'='FAQPage'; mainEntity=$faqEntities }
    )
    $schema = (@{ '@context'='https://schema.org'; '@graph'=$schemaGraph } | ConvertTo-Json -Depth 10 -Compress)

    # ---- Section ordering ----
    # Every content section between the trust strip and the final CTA is
    # built as its own self-contained <section> above, then assembled here
    # in whatever order this page's config specifies (or the default order,
    # which reproduces the original fixed layout so existing pages don't
    # need a "section_order" key at all).
    $sectionsMap = [ordered]@{
        'INTRO_SECTION' = $introSection
        'ABOUT_SECTION' = $aboutSectionHtml
        'FEATURED_TOURS' = $featuredToursSectionHtml
        'EXPERIENCE_COMPARISON' = $experienceComparisonHtml
        'CURATED_JOURNEYS' = $curatedJourneysHtml
        'TOUR_SELECTOR' = $tourSelectorHtml
        'SECONDARY_SELECTOR' = $secondarySelectorHtml
        'EXPECTATIONS' = $expectationsHtml
        'PICKUP_SECTION' = $pickupSectionHtml
        'TRAVEL_TIMES' = $travelTimesSectionHtml
        'TRAVELER_TYPES' = $travelerTypesHtml
        'AUDIENCE_SECTIONS' = $audienceSectionsHtml
        'WHY_PRIVATE' = $whyPrivateSectionHtml
        'FAMILIES_SECTION' = $familiesSectionHtml
        'AIRPORT_SECTION' = $airportSectionHtml
        'HOTEL_CROSSLINK' = $hotelCrosslinkHtml
        'EDITORIAL_CROSSLINK' = $editorialCrosslinkHtml
        'FAQ_SECTION' = $faqSectionWrapped
    }
    $defaultSectionOrder = @('INTRO_SECTION','FEATURED_TOURS','CURATED_JOURNEYS','TOUR_SELECTOR','SECONDARY_SELECTOR','PICKUP_SECTION','TRAVEL_TIMES','TRAVELER_TYPES','AUDIENCE_SECTIONS','WHY_PRIVATE','AIRPORT_SECTION','HOTEL_CROSSLINK','FAQ_SECTION')
    $sectionOrder = @(Get-PropertyValue $c 'section_order' $defaultSectionOrder)
    $mainSectionsHtml = (($sectionOrder | ForEach-Object {
        if ($_ -like 'DECISION_BLOCK:*') {
            $dbName = $_.Substring('DECISION_BLOCK:'.Length)
            if ($decisionBlocksMap.Contains($dbName)) { $decisionBlocksMap[$dbName] } else { '' }
        } elseif ($_ -like 'CONTENT_BLOCK:*') {
            $cbName = $_.Substring('CONTENT_BLOCK:'.Length)
            if ($contentBlocksMap.Contains($cbName)) { $contentBlocksMap[$cbName] } else { '' }
        } elseif ($sectionsMap.Contains($_)) { $sectionsMap[$_] } else { '' }
    }) -join "`n`n")

    # ---- Assemble ----
    $html = $template.Replace('__COMPONENT_HEADER__', $header).Replace('__COMPONENT_FOOTER__', $footer)
    $replacements = [ordered]@{
        '__SEO_TITLE__' = [string]$c.seo_title
        '__SEO_DESCRIPTION__' = [string]$c.seo_description
        '__CANONICAL__' = $canonical
        '__OG_IMAGE__' = "$siteUrl/$([string]$c.og_image)"
        '__SCHEMA__' = $schema
        '__HERO_SECTION__' = $heroSection
        '__TRUST_STRIP__' = $trustStrip
        '__PARENT_HUB_LINK__' = $parentHubLinkHtml
        '__MAIN_SECTIONS__' = $mainSectionsHtml
        '__FINAL_CTA__' = $finalCtaHtml
    }
    foreach ($key in $replacements.Keys) { $html = $html.Replace($key, [string]$replacements[$key]) }

    $outPath = Join-Path $outDir "$($c.slug).html"
    Write-FileIfChanged -Path $outPath -Content $html
    Write-Host "Generated landing page: $outDirName/$($c.slug).html"
    $count++
}
Write-Host "Landing Page Engine complete: $count page(s)."

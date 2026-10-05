# ============================================================
# Wild Papagayo - Hotels Index Generator v1.0
# Builds hotels.html: a real listing page linking to all published
# hotel guide pages (knowledge/hotels/*.json), so visitors have a
# single place to browse partner hotels instead of relying on
# incidental links from destination/blog pages.
# Usage: .\hotels-index-generator.ps1
# ============================================================

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Write-FileIfChanged {
    param([string]$Path, [string]$Content)
    if ((Test-Path $Path) -and ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) -ceq $Content)) { return }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}
$root = $PSScriptRoot
$hotelDir = Join-Path $root "knowledge\hotels"
$siteUrl = "https://wildpapagayo.com"
$outPath = Join-Path $root "hotels.html"

function Get-PropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}
function ConvertTo-HtmlSafe {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    return $Text.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}
function Get-StarHtml {
    param([double]$Score)
    $rounded = [Math]::Round($Score)
    if ($rounded -lt 0) { $rounded = 0 }
    if ($rounded -gt 5) { $rounded = 5 }
    $html = '<span class="hi-stars" aria-label="' + $Score.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture) + ' out of 5">'
    for ($i=1; $i -le 5; $i++) {
        $class = if ($i -le $rounded) { 'hi-star is-filled' } else { 'hi-star' }
        $html += '<svg class="' + $class + '" viewBox="0 0 24 24" aria-hidden="true"><path d="m12 2.5 2.9 5.9 6.5.9-4.7 4.6 1.1 6.5-5.8-3.1-5.8 3.1 1.1-6.5-4.7-4.6 6.5-.9L12 2.5Z"/></svg>'
    }
    $html += '</span>'
    return $html
}
function Get-GoogleBadgeHtml {
    return '<span class="hi-google-badge" title="Sourced from Google"><svg viewBox="0 0 48 48" aria-hidden="true"><path fill="#4285F4" d="M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17Z"/><path fill="#34A853" d="M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46Z"/><path fill="#FBBC05" d="M11.69 28.18A13.5 13.5 0 0 1 10.98 24c0-1.45.25-2.86.71-4.18v-5.7H4.34A21.99 21.99 0 0 0 2 24c0 3.55.85 6.91 2.34 9.88l7.35-5.7Z"/><path fill="#EA4335" d="M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07Z"/></svg></span>'
}

$hotels = @()
foreach ($file in @(Get-ChildItem $hotelDir -Filter "*.json" -File | Sort-Object Name)) {
    $h = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    # Strict eligibility gate -- see hotel-generator.ps1 for the reasoning:
    # only an explicit "published" is eligible, not merely "not disabled".
    if ([string](Get-PropertyValue $h "status" "review") -ne "published") { continue }
    $hotels += $h
}

# Real destination names for grouping -- so the list stays scannable as the
# portfolio grows past a dozen properties (groups of ~5-10, not one long list).
$destinationsDir = Join-Path $root "knowledge\destinations"
$destNameById = @{}
$destPublishedById = @{}
if (Test-Path $destinationsDir) {
    foreach ($df in Get-ChildItem $destinationsDir -Filter "*.json" -File) {
        $d = [System.IO.File]::ReadAllText($df.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $destNameById[$df.BaseName] = [string](Get-PropertyValue $d "name" $df.BaseName)
        # Only a destination with status "published" may be linked publicly.
        if ([string](Get-PropertyValue $d "status" "") -eq "published") { $destPublishedById[$df.BaseName] = $true }
    }
}

# Real, computed-fresh-every-build hero stat (replaces a Google-sourced photo
# we don't hold rights to). Only hotels with an actual Google rating count --
# no fabricated numbers for "recently added" properties.
$ratedHotels = @($hotels | Where-Object { $_.google_reviews -and $_.google_reviews.rating })
$avgRating = if ($ratedHotels.Count -gt 0) {
    ($ratedHotels | ForEach-Object { [double]$_.google_reviews.rating } | Measure-Object -Average).Average
} else { 0 }
$avgRatingText = $avgRating.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)

$ratingBarsHtml = ""
foreach ($rh in $hotels) {
    $rProp = Get-PropertyValue $rh 'google_reviews' $null
    $r = if ($rProp) { Get-PropertyValue $rProp 'rating' $null } else { $null }
    if ($null -eq $r) { continue }
    $rVal = [double]$r
    $heightPct = [Math]::Round(($rVal / 5) * 100)
    $rText = $rVal.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
    $ratingBarsHtml += '<div class="hi-hero-bar" style="height:' + $heightPct + '%" title="' + (ConvertTo-HtmlSafe ([string]$rh.name)) + ' -- ' + $rText + ' / 5 on Google"></div>'
}

$itemListElements = @()
$position = 0

# Group by real destination_id so the page reads as a curated index (a
# handful of hotels per destination) rather than one long undifferentiated
# grid -- this is what keeps it scannable once the portfolio passes ~20-30
# properties, not just at the current 12.
$groups = $hotels | Group-Object -Property destination_id | Sort-Object Count -Descending

$groupsHtml = ""
foreach ($group in $groups) {
    $destId = [string]$group.Name
    $destName = if ($destNameById.ContainsKey($destId)) { $destNameById[$destId] } else { $destId }
    $destLink = if ($destPublishedById.ContainsKey($destId)) { '<a href="destinations/' + $destId + '">' + (ConvertTo-HtmlSafe $destName) + ' guide &rarr;</a>' } else { '' }
    $countLabel = if ($group.Count -eq 1) { "1 hotel" } else { "$($group.Count) hotels" }

    $rowsHtml = ""
    foreach ($h in $group.Group) {
        $position++
        $slug = [string]$h.slug
        $name = [string]$h.name
        $location = [string]$h.location_label
        $category = [string]$h.category
        $url = "hotels/$slug"
        $googleReviews = Get-PropertyValue $h "google_reviews" $null

        $ratingHtml = ""
        if ($googleReviews -and $googleReviews.rating) {
            $ratingText = ([double]$googleReviews.rating).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
            $ratingHtml = '<span class="hi-idx-rating"><strong>' + $ratingText + '</strong><small>' + [string]$googleReviews.review_count + '</small></span>'
        } else {
            $ratingHtml = '<span class="hi-idx-rating hi-idx-rating-pending"><small>Recently added</small></span>'
        }

        $rowsHtml += '<a class="hi-idx-row" href="' + $url + '">' +
            '<span class="hi-idx-name"><span class="hi-idx-loc">' + (ConvertTo-HtmlSafe $location) + '</span><h3>' + (ConvertTo-HtmlSafe $name) + '</h3></span>' +
            '<span class="hi-idx-cat">' + (ConvertTo-HtmlSafe $category) + '</span>' +
            $ratingHtml +
            '</a>'

        $itemEntry = [ordered]@{"@type"="ListItem";position=$position;url="$siteUrl/$url"}
        $itemListElements += $itemEntry
    }

    $groupsHtml += '<div class="hi-group"><div class="hi-group-head"><h2>' + (ConvertTo-HtmlSafe $destName) + '</h2><span class="hi-group-meta">' + $countLabel + $destLink + '</span></div><div class="hi-idx-list">' + $rowsHtml + '</div></div>'
}

$schemaGraph = @(
    [ordered]@{"@type"="TravelAgency";"@id"="$siteUrl/#organization";name="Wild Papagayo";url="$siteUrl/"},
    [ordered]@{"@type"="CollectionPage";"@id"="$siteUrl/hotels#webpage";name="Best Hotels in Papagayo, Costa Rica";url="$siteUrl/hotels";description="Luxury resorts and hotels in Peninsula Papagayo and the Gulf of Papagayo, with real Google ratings, verified transfer times and local travel guidance.";publisher=[ordered]@{"@id"="$siteUrl/#organization"}},
    [ordered]@{"@type"="ItemList";itemListElement=$itemListElements},
    [ordered]@{"@type"="BreadcrumbList";itemListElement=@(
        [ordered]@{"@type"="ListItem";position=1;name="Home";item="$siteUrl/"},
        [ordered]@{"@type"="ListItem";position=2;name="Hotels";item="$siteUrl/hotels"}
    )}
)
$schema = @{"@context"="https://schema.org";"@graph"=$schemaGraph} | ConvertTo-Json -Depth 10 -Compress

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" /><link rel="icon" type="image/svg+xml" href="images/favicon-wildpapagayo.svg">
    <meta content="width=device-width, initial-scale=1.0" name="viewport" />
    <title>Best Hotels in Papagayo, Costa Rica | Luxury Resort Guide</title>
    <meta name="description" content="Compare luxury resorts and hotels in Peninsula Papagayo and the Gulf of Papagayo, with real Google ratings, verified transfer times and private tour options.">
    <meta name="robots" content="index, follow">
    <meta name="author" content="Wild Papagayo">
    <meta name="theme-color" content="#062448">
    <link rel="canonical" href="$siteUrl/hotels">

    <meta property="og:title" content="Best Hotels in Papagayo, Costa Rica | Luxury Resort Guide">
    <meta property="og:description" content="Compare luxury resorts and hotels across Papagayo, Costa Rica, with real Google ratings and verified travel details, curated by Wild Papagayo.">
    <meta property="og:image" content="$siteUrl/images/luxury-costa-rica-tours-hero.webp">
    <meta property="og:type" content="website">
    <meta property="og:url" content="$siteUrl/hotels">

    <script type="application/ld+json">
    $schema
    </script>

    <link rel="preload" href="style.min.css" as="style">
    <link href="style.min.css" rel="stylesheet" />

    <style>
    .hi-section{padding:64px 0 90px}
    .hi-group{margin-bottom:46px}
    .hi-group:last-child{margin-bottom:0}
    .hi-group-head{display:flex;align-items:baseline;justify-content:space-between;gap:16px;flex-wrap:wrap;border-bottom:2px solid #062448;padding-bottom:10px;margin-bottom:6px}
    .hi-group-head h2{font-family:'Playfair Display',Georgia,serif;font-size:1.5rem;color:#062448;margin:0}
    .hi-group-meta{font-size:.78rem;color:var(--muted);display:flex;align-items:center;gap:14px}
    .hi-group-meta a{color:#062448;font-weight:800;text-decoration:none!important}
    .hi-group-meta a:hover{text-decoration:underline!important}
    .hi-idx-list{border-top:1px solid #e5ded1}
    .hi-idx-row{display:grid;grid-template-columns:1.3fr 1fr auto;gap:18px;align-items:center;padding:16px 6px;border-bottom:1px solid #e5ded1;text-decoration:none!important;color:inherit!important;transition:.15s}
    .hi-idx-row:hover{background:#fff}
    .hi-idx-loc{display:block;font-size:.62rem;letter-spacing:.1em;text-transform:uppercase;color:#c99a2e;font-weight:800;margin-bottom:3px}
    .hi-idx-name h3{font-family:'Playfair Display',Georgia,serif;font-size:1.08rem;margin:0;color:#062448;line-height:1.25}
    .hi-idx-cat{font-size:.82rem;color:var(--muted)}
    .hi-idx-rating{display:flex;align-items:baseline;gap:5px;white-space:nowrap;justify-self:end}
    .hi-idx-rating strong{font-family:'Playfair Display',Georgia,serif;font-size:1.2rem;color:#062448}
    .hi-idx-rating small{font-size:.68rem;color:var(--muted)}
    .hi-idx-rating-pending small{color:var(--muted);font-style:italic}
    @media(max-width:650px){.hi-idx-row{grid-template-columns:1fr auto;row-gap:5px}.hi-idx-cat{grid-column:1;font-size:.76rem}}
    .hi-hero-stat{display:inline-flex;align-items:center;gap:14px;margin:24px 0 0;padding:14px 22px;background:#062448;border-radius:10px}
    .hi-hero-stat strong{font-family:'Playfair Display',Georgia,serif;font-size:2.1rem;color:#f4ead2;display:flex;align-items:baseline;gap:5px;line-height:1}
    .hi-hero-stat strong span{color:#c99a2e;font-size:1.2rem}
    .hi-hero-stat-copy{text-align:left}
    .hi-hero-stat-copy span{display:block;font-size:.68rem;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:#fff}
    .hi-hero-stat-copy small{display:block;font-size:.78rem;color:rgba(255,255,255,.6);margin-top:2px}
    .hi-hero-bars{display:flex;align-items:flex-end;justify-content:center;gap:5px;height:56px;margin:22px auto 4px;width:min(92%,420px)}
    .hi-hero-bar{flex:1;min-width:6px;max-width:16px;background:#c99a2e;border-radius:3px 3px 0 0;opacity:.8;transition:opacity .2s,transform .2s;cursor:default}
    .hi-hero-bar:hover{opacity:1;transform:scaleY(1.05)}
    @media(max-width:650px){.hi-hero-stat{flex-direction:column;text-align:center;gap:6px}.hi-hero-stat-copy{text-align:center}}
    .tours-faq-item{border-bottom:1px solid #e5ded1;padding:18px 0}
    .tours-faq-item:last-child{border-bottom:none}
    .tours-faq-item h3{font-family:'Playfair Display',Georgia,serif;font-size:1.05rem;color:#062448;margin:0 0 8px}
    .tours-faq-item p{color:#4a5568;font-size:.92rem;line-height:1.6;margin:0}
    </style>

<!-- Google tag (gtag.js) -- deferred until window 'load' so it never competes with LCP/FCP-critical resources -->
<script>
window.addEventListener('load', function() {
  var s = document.createElement('script');
  s.async = true;
  s.src = 'https://www.googletagmanager.com/gtag/js?id=G-9V2MY7J6RJ';
  document.head.appendChild(s);
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  window.gtag = gtag;
  gtag('js', new Date());
  gtag('config', 'G-9V2MY7J6RJ');
});
</script>
</head>
<body><a class="skip-to-content" href="#main-content">Skip to main content</a>
    <header class="site-header">
    <nav class="nav container" aria-label="Main navigation">
        <a class="brand" href="/" aria-label="Wild Papagayo Home">
            <img src="images/logo-wildpapagayo-nav.webp" alt="Wild Papagayo Private Journeys Costa Rica" width="160" height="80" loading="eager" fetchpriority="high" decoding="async">
        </a>
        <button aria-label="Open menu" aria-expanded="false" aria-controls="main-navigation" class="hamburger">&#9776;</button>
        <div class="nav-links" id="main-navigation">
            <a href="/">Home</a>
            <a href="tours">All Experiences</a>
            <a href="paquete">Multi-Day Journeys</a>
            <div class="nav-dropdown">
                <button class="nav-dropdown-trigger" aria-expanded="false" aria-haspopup="true">Discover <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg></button>
                <div class="nav-dropdown-menu">
                    <a href="destination-finder">Destinations</a>
                    <a href="hotels">Hotels</a>
                    <a href="private-tours/peninsula-papagayo">Tours from Papagayo</a>
                    <a href="months">When to Visit</a>
                    <a href="blog/liberia-airport-transfer-guide">Liberia Airport Guide</a>
                    <a href="waterfalls-near-papagayo-guide">Waterfalls Near Papagayo</a>
                    <a href="plan-by-traveler-type">Plan by Traveler Type</a>
                </div>
            </div>
            <a href="transport">Transport</a>
            <a href="guides">Expert Guides</a>
            <a href="about">Our Story</a>
            <a href="Blogs">Insider Guide</a>
            <a href="travel-insurance">Travel Insurance</a>
            <a href="contact">Connect</a>
        </div>
        <a class="btn btn-primary header-cta" href="https://wa.me/50688566325?text=Hello%20Wild%20Papagayo!%20I%20want%20to%20plan%20my%20Costa%20Rica%20trip." target="_blank" rel="noopener noreferrer">Plan Your Trip</a>
    </nav>
</header>

    <main id="main-content">
        <header class="plain-hero">
            <div class="container plain-hero-inner">
                <h1>Hotels &amp; Luxury Resorts in Papagayo, Costa Rica</h1>
                <p>Planning a stay in Papagayo, Costa Rica? This local guide highlights luxury resorts, beachfront hotels and popular places to stay across Peninsula Papagayo and the Gulf of Papagayo. Compare locations, resort styles, nearby beaches, airport transportation and private tour options before choosing the right hotel for your trip.</p>
                <p>Whether you're considering Four Seasons, Andaz, Nekajui, Riu Guanacaste, Planet Hollywood, El Mangroove or another Guanacaste hotel, Wild Papagayo can help you connect your stay with private transportation and personalized day tours.</p>
                <div class="hi-hero-stat">
                    <strong>$avgRatingText<span>&#9733;</span></strong>
                    <div class="hi-hero-stat-copy"><span>Average Google Rating</span><small>Across $($ratedHotels.Count) rated properties in our portfolio</small></div>
                </div>
                <div class="hi-hero-bars" role="img" aria-label="Real Google ratings for each partner hotel, out of 5 stars">$ratingBarsHtml</div>
            </div>
        </header>

        <section class="hi-section" style="padding-bottom:0;">
            <div class="container" style="max-width:820px;">
                <span class="section-kicker">Guanacaste's Home Base</span>
                <h2 class="section-title">Best Hotels in Papagayo, Costa Rica</h2>
                <p style="color:#4a5568;font-size:1rem;line-height:1.7;margin:16px 0 0;">Papagayo is one of Guanacaste's most popular areas for luxury resorts, calm beaches and easy access to Liberia International Airport. Hotels range from secluded Peninsula Papagayo resorts to beachfront properties around the Gulf of Papagayo.</p>
            </div>
        </section>

        <section class="hi-section">
            <div class="container">
                $groupsHtml
            </div>
        </section>

        <section class="section" style="background:#f7f4ee;">
            <div class="container" style="max-width:820px;">
                <div class="section-head reveal"><span class="section-kicker">Compare Areas</span><h2 class="section-title">Which Papagayo Hotel Area Is Right for You?</h2></div>
                <div style="overflow-x:auto;margin:24px 0 0;">
                    <table style="width:100%;border-collapse:collapse;font-size:.92rem;">
                        <thead><tr style="background:#062448;color:#fff;">
                            <th style="padding:10px 14px;text-align:left;">Area</th>
                            <th style="padding:10px 14px;text-align:left;">Best For</th>
                            <th style="padding:10px 14px;text-align:left;">Atmosphere</th>
                        </tr></thead>
                        <tbody>
                            <tr style="border-bottom:1px solid #e5ded1;"><td style="padding:10px 14px;">Peninsula Papagayo</td><td style="padding:10px 14px;">Luxury &amp; privacy</td><td style="padding:10px 14px;">Exclusive</td></tr>
                            <tr style="border-bottom:1px solid #e5ded1;background:#fff;"><td style="padding:10px 14px;">Gulf of Papagayo</td><td style="padding:10px 14px;">Resorts &amp; beaches</td><td style="padding:10px 14px;">Relaxed</td></tr>
                            <tr style="border-bottom:1px solid #e5ded1;"><td style="padding:10px 14px;">Playa Hermosa</td><td style="padding:10px 14px;">Beach access</td><td style="padding:10px 14px;">Quiet</td></tr>
                            <tr style="background:#fff;"><td style="padding:10px 14px;">Playa del Coco</td><td style="padding:10px 14px;">Restaurants &amp; activity</td><td style="padding:10px 14px;">Lively</td></tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </section>

        <section class="section">
            <div class="container" style="max-width:820px;text-align:center;">
                <span class="section-kicker">Airport Transportation</span>
                <h2 class="section-title">Getting From Liberia Airport to Your Papagayo Hotel</h2>
                <p style="color:#4a5568;font-size:1rem;line-height:1.7;margin:16px 0 24px;">Liberia International Airport (LIR) is the main airport for travelers staying in Papagayo and northern Guanacaste. Private transportation can be arranged directly from the airport to resorts across Peninsula Papagayo and the Gulf of Papagayo.</p>
                <a class="btn btn-secondary" style="background:transparent;color:#062448;border:1.5px solid #062448;" href="blog/liberia-airport-transfer-guide">Read Our Liberia Airport Transportation Guide &rarr;</a>
            </div>
        </section>

        <section class="section" style="background:#f7f4ee;">
            <div class="container" style="max-width:820px;text-align:center;">
                <span class="section-kicker">Tours &amp; Excursions</span>
                <h2 class="section-title">Private Tours From Papagayo Hotels</h2>
                <p style="color:#4a5568;font-size:1rem;line-height:1.7;margin:16px 0 24px;">Staying in Papagayo also makes it easy to explore waterfalls, wildlife, volcanoes and adventure destinations throughout Guanacaste. Wild Papagayo offers private tours with hotel pickup from many resorts in the area.</p>
                <a class="btn btn-secondary" style="background:transparent;color:#062448;border:1.5px solid #062448;" href="tours">Explore Papagayo Tours &rarr;</a>
            </div>
        </section>

        <section class="section" style="padding-bottom:56px;">
            <div class="container" style="max-width:760px;">
                <div class="section-head reveal" style="text-align:center;"><span class="section-kicker">Questions</span><h2 class="section-title">Frequently Asked Questions</h2></div>
                <div style="margin-top:20px;">
                    <div class="tours-faq-item">
                        <h3>What are the best luxury hotels in Papagayo, Costa Rica?</h3>
                        <p>Four Seasons Resort Costa Rica, Andaz Peninsula Papagayo and Nekajui, A Ritz-Carlton Reserve are the three luxury properties within Peninsula Papagayo itself, with more resorts around the wider Gulf of Papagayo.</p>
                    </div>
                    <div class="tours-faq-item">
                        <h3>Which hotels are located in Peninsula Papagayo?</h3>
                        <p>Four Seasons Resort Costa Rica, Andaz Peninsula Papagayo and Nekajui, A Ritz-Carlton Reserve sit directly within Peninsula Papagayo. Other Wild Papagayo partner hotels are located around the wider Gulf of Papagayo and nearby beach towns, each noted on its listing below.</p>
                    </div>
                    <div class="tours-faq-item">
                        <h3>How far is Papagayo from Liberia Airport?</h3>
                        <p>Most resorts in the Papagayo area are about 30 to 45 minutes from Liberia International Airport (LIR) by private transfer.</p>
                    </div>
                    <div class="tours-faq-item">
                        <h3>Is Papagayo a good area for families?</h3>
                        <p>Yes. Papagayo's calm gulf waters and resort-style properties suit families well, and private tours can be paced around children.</p>
                    </div>
                    <div class="tours-faq-item">
                        <h3>Can I book private transportation to my Papagayo hotel?</h3>
                        <p>Yes. Wild Papagayo can arrange private transfers from Liberia International Airport directly to your resort.</p>
                    </div>
                    <div class="tours-faq-item">
                        <h3>Can Wild Papagayo pick us up directly from our resort for tours?</h3>
                        <p>Yes. Most of our private tours include direct hotel pickup from Papagayo-area resorts.</p>
                    </div>
                </div>
            </div>
        </section>

        <section style="background:#062448;padding:82px 0;text-align:center;">
            <div class="container" style="max-width:680px;">
                <p style="font-size:.85rem;font-weight:700;color:#C9A24B;margin-bottom:12px;">Staying in Papagayo?</p>
                <h2 style="font-family:'Playfair Display',Georgia,serif;font-size:clamp(1.7rem,4vw,2.6rem);color:#fff;margin:0 0 16px;line-height:1.2;">Let Us Help Plan the Rest of Your Trip</h2>
                <p style="color:rgba(255,255,255,.70);font-size:1rem;line-height:1.7;margin:0 0 32px;">Tell us where you're staying and what you'd like to experience. We can help arrange private airport transportation and personalized tours from your hotel.</p>
                <div style="display:flex;gap:14px;flex-wrap:wrap;justify-content:center;">
                    <a class="btn btn-primary" data-cta-location="hotels_page_main" data-intent="book_tour" href="tours">Explore Tours</a>
                    <a class="btn btn-secondary" style="border-color:#fff;color:#fff;" data-cta-location="hotels_page_main" data-intent="airport_transfer" href="https://wa.me/50688566325?text=Hello%20Wild%20Papagayo!%20I%27d%20like%20to%20ask%20about%20private%20transportation%20to%20my%20Papagayo%20hotel." target="_blank" rel="noopener noreferrer">Ask About Transportation</a>
                </div>
            </div>
        </section>
    </main>

    <footer class="footer">
    <div class="container footer-grid footer-grid-clean">

        <div class="footer-brand">
            <img src="images/logo-wildpapagayo-nav.webp" alt="Wild Papagayo Private Journeys Costa Rica" class="footer-logo" width="180" height="180">
            <p>Exceptional Costa Rica, exclusively curated for discerning travelers.</p>
            <div class="footer-social">
                <a href="https://www.instagram.com/wild.papagayo" target="_blank" rel="noopener noreferrer" aria-label="Instagram" class="footer-social-ig">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="2" width="20" height="20" rx="5" ry="5"/><path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z"/><line x1="17.5" y1="6.5" x2="17.51" y2="6.5"/></svg>
                </a>
                <a href="https://www.facebook.com/share/1JLByXiV4k/?mibextid=wwXIfr" target="_blank" rel="noopener noreferrer" aria-label="Facebook" class="footer-social-fb">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 2h-3a5 5 0 0 0-5 5v3H7v4h3v8h4v-8h3l1-4h-4V7a1 1 0 0 1 1-1h3z"/></svg>
                </a>
                <a href="https://wa.me/50688566325" target="_blank" rel="noopener noreferrer" aria-label="WhatsApp" class="footer-social-wa">
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0 0 12.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 0 0 5.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 0 0-3.48-8.413z"/></svg>
                </a>
            </div>
        </div>

        <div>
            <div class="footer-title">Explore</div>
            <a href="/">Home</a>
            <a href="tours">All Experiences</a>
            <a href="paquete">Multi-Day Journeys</a><a href="hotels">Hotels</a>
            <a href="transport">Transport</a>
            <a href="guides">Expert Guides</a>
            <a href="about">Our Story</a>
            <a href="Blogs">Insider Guide</a>
            <a href="travel-insurance">Travel Insurance</a>
            <div class="footer-title footer-title-spaced">Legal</div>
            <a href="Terminosycondiciones">Terms &amp; Conditions</a>
            <a href="politicasdecancelacion">Booking &amp; Cancellation Policy</a>
            <a href="politicasdeprivacidad">Privacy Policy</a>
        </div>

        <div>
            <div class="footer-title">Get in Touch</div>
            <div class="footer-contact">
                <p>Guanacaste, Costa Rica</p>
                <p><a href="tel:+50688566325">+506 8856-6325</a></p>
                <p><a href="mailto:info@wildpapagayo.com">info@wildpapagayo.com</a></p>
            </div>
            <p class="footer-ict">Costa Rica - ICT License #491</p>
        </div>

        <div>
            <div class="footer-title">Trip Planning Tips</div>
            <p>Real trip-planning tips, seasonal advice and new tours from our local team. No spam, unsubscribe anytime.</p>
            <div class="newsletter-form">
                <label for="newsletterEmail" class="sr-only">Email</label>
                <input id="newsletterEmail" name="newsletterEmail" type="email" placeholder="Your email address" required>
                <button class="btn-newsletter" type="button" id="btnNewsletterReal" onclick="enviarNewsletter()">Join</button>
            </div>
        </div>

    </div>

    <div class="container footer-bottom">
        &copy; <span id="year"></span> Wild Papagayo. All rights reserved.
    </div>
</footer>

<a href="https://wa.me/50688566325?text=Hello%20Wild%20Papagayo!%20I%20want%20to%20plan%20a%20private%20Costa%20Rica%20experience."
   class="whatsapp-float" target="_blank" rel="noopener noreferrer" aria-label="Chat with us on WhatsApp">
    <svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="currentColor"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0 0 12.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 0 0 5.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 0 0-3.48-8.413z"/></svg>
</a>

    <script src="script.js" defer></script><script src="assistant-widget.js" defer></script>
</body>
</html>
"@

Write-FileIfChanged -Path $outPath -Content $html
Write-Host "Generated hotels.html with $($hotels.Count) hotels" -ForegroundColor Green

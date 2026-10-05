# ============================================================
# Wild Papagayo - Month Engine v1.0
# Generates /months/january.html ... december.html from
# knowledge/seasons.json (month + season group ids) and the
# season_ids already tagged on blog-data.json articles and
# knowledge/tours/*.json. Reuses the destination.html visual
# language (same CSS classes) for consistency.
# ============================================================
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

$root = $PSScriptRoot
$templatePath = Join-Path $root "templates/month.html"
$outputDir = Join-Path $root "months"
$blogPath = Join-Path $root "blog-data.json"
$seasonsPath = Join-Path $root "knowledge/seasons.json"
$toursDir = Join-Path $root "knowledge/tours"
$destinationsDir = Join-Path $root "knowledge/destinations"
$siteUrl = "https://wildpapagayo.com"

if (-not (Test-Path $templatePath)) { throw "Missing template: $templatePath" }
New-Item -ItemType Directory -Force $outputDir | Out-Null

function Read-Utf8Json([string]$path) { return ([System.IO.File]::ReadAllText($path) | ConvertFrom-Json) }
function ConvertTo-HtmlSafe([object]$value) { return [System.Net.WebUtility]::HtmlEncode([string]$value) }
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

$template = [System.IO.File]::ReadAllText($templatePath)
$header = Component "header"
$footer = Component "footer"
$ctaTemplate = Component "cta"
$articles = if (Test-Path $blogPath) { @(Read-Utf8Json $blogPath) } else { @() }
$seasons = @(Read-Utf8Json $seasonsPath)
$heroImage = "images/luxury-costa-rica-tours-hero.webp"

$tours = @()
if (Test-Path $toursDir) {
    $tours = Get-ChildItem $toursDir -Filter '*.json' -File | ForEach-Object {
        $t = Read-Utf8Json $_.FullName
        [pscustomobject]@{
            id = [string]$t.id
            name = [string]$t.name
            category = [string]$t.category
            description = [string]$t.short_description
            image = [string]$t.hero_image
            page_url = [string]$t.page_url
        }
    }
}

$destinations = @()
if (Test-Path $destinationsDir) {
    $destinations = Get-ChildItem $destinationsDir -Filter '*.json' -File | ForEach-Object {
        $dRec = Read-Utf8Json $_.FullName
        # Strict publication gate: only status "published" may get a month-page card.
        if ([string]$dRec.status -ne 'published') { return }
        $dRec
    }
}

$monthOrder = @('january','february','march','april','may','june','july','august','september','october','november','december')

# Group membership (dry-season / green-season) for each month, from seasons.json
$groupOf = @{}
foreach ($s in $seasons) {
    if (@('dry-season','green-season') -contains $s.id) {
        foreach ($m in @($s.month_ids)) { $groupOf[$m] = $s.id }
    }
}

$weatherBody = @{
    'january'   = "January sits at the heart of Guanacaste's dry season. Expect long stretches of sun, low humidity and calm seas, one of the most reliable months for beach days, boat tours and hiking without rain interruptions. Trade winds pick up toward the end of the month, so mornings on the water tend to be calmer than afternoons."
    'february'  = "February is peak dry season: minimal rainfall, strong sun and steady winds across the Papagayo Peninsula. It's an excellent month for hiking, ziplining and full-day tours, though windier afternoons can affect catamaran comfort on open water."
    'march'     = "March continues the dry-season pattern, clear skies, warm temperatures and very little rain. Vegetation starts looking drier and dustier by late March, which is normal for Guanacaste's tropical dry forest ecosystem, but wildlife stays active around remaining water sources."
    'april'     = "April is typically the hottest month of the year in Guanacaste, still within the dry season but with rising humidity as the transition toward green season approaches. Early tours and hydration matter more this month than any other."
    'may'       = "May marks the start of green season. Expect a mostly sunny morning followed by a short, powerful afternoon shower, rarely enough to cancel plans, but worth building tours around a morning start. The landscape turns vividly green almost overnight."
    'june'      = "June is solidly green season, with rainfall that varies day to day rather than following a fixed schedule. Late June can bring the veranillo de San Juan, a historical pattern of a few drier, sunnier days -- not something to count on, but a welcome stretch when it happens. Rivers and waterfalls run fuller than during dry season, and crowds are noticeably lighter at major attractions."
    'july'      = "July continues green season's usual rhythm, with the same day-to-day variability as June. In some years, the tail end of June's veranillo de San Juan stretches into the first days of July. Rainforest tours are at their most lush and wildlife-active this month."
    'august'    = "August continues green-season patterns with warm mornings and dependable afternoon rain. It's a strong month for waterfall and hot springs tours, since water levels are high and trails are cooler than peak dry season."
    'september' = "September is one of the wettest months in Guanacaste, with rain arriving earlier in the day at times. It's also one of the quietest months for tourism, which means better availability and a genuinely local pace, mornings still tend to be clear enough for tours."
    'october'   = "October is typically the rainiest month of the year. Plan tours for mornings, keep itineraries flexible, and expect the most dramatic waterfalls and green scenery of the year. Some remote roads may be affected by heavy rain."
    'november'  = "November is a transition month, rain frequency starts dropping and the dry season begins to reassert itself toward the end of the month. It's an underrated time to visit: lush landscapes, thinner crowds and improving weather."
    'december'  = "December marks the return of the dry season, with rain tapering off and sunny days becoming the norm again by mid-month. It's also peak holiday travel season, so book tours and transfers early."
}

function Get-BestForMonth {
    param([string]$MonthId, $Destination)
    $best = [string]$Destination.best_season
    if (-not $best) { return $true }
    if ($best -match 'Year-round') { return $true }
    $monthIdx = $monthOrder.IndexOf($MonthId)
    $rangeMonths = $monthOrder | Where-Object { $best -match ([regex]::Escape((Get-Culture).TextInfo.ToTitleCase($_))) }
    if ($rangeMonths.Count -eq 0) { return $false }
    $rangeIdx = @($rangeMonths | ForEach-Object { $monthOrder.IndexOf($_) })
    if ($rangeIdx.Count -ge 2) {
        $lo = ($rangeIdx | Measure-Object -Minimum).Minimum
        $hi = ($rangeIdx | Measure-Object -Maximum).Maximum
        if ($lo -le $hi) { return ($monthIdx -ge $lo -and $monthIdx -le $hi) }
        else { return ($monthIdx -ge $lo -or $monthIdx -le $hi) }
    }
    return ($rangeIdx -contains $monthIdx)
}

$monthEntries = @($seasons | Where-Object { $monthOrder -contains $_.id })
$generated = 0

for ($i = 0; $i -lt $monthOrder.Count; $i++) {
    $monthId = $monthOrder[$i]
    $monthEntry = $monthEntries | Where-Object { $_.id -eq $monthId } | Select-Object -First 1
    $monthName = if ($monthEntry) { [string]$monthEntry.name } else { (Get-Culture).TextInfo.ToTitleCase($monthId) }
    $group = $groupOf[$monthId]
    $groupLabel = if ($group -eq 'dry-season') { 'Dry Season' } elseif ($group -eq 'green-season') { 'Green Season' } else { 'Year-round' }
    $canonical = "$siteUrl/months/$monthId"

    $quickFacts = @(
        @{Label='Season';Value=$groupLabel},
        @{Label='Best for';Value=if ($group -eq 'dry-season') { 'Beaches & hiking' } else { 'Waterfalls & wildlife' }},
        @{Label='Crowds';Value=if (@('december','january','february','march') -contains $monthId) { 'Peak season' } elseif (@('september','october') -contains $monthId) { 'Quietest months' } else { 'Moderate' }},
        @{Label='Rain risk';Value=if ($group -eq 'dry-season') { 'Low' } elseif (@('september','october') -contains $monthId) { 'High' } else { 'Moderate' }}
    ) | ForEach-Object { "<div class=`"destination-fact`"><small>$(ConvertTo-HtmlSafe ($_.Label))</small><strong>$(ConvertTo-HtmlSafe ($_.Value))</strong></div>" }

    # Destinations that fit this month
    $destCards = @()
    foreach ($d in $destinations) {
        if (Get-BestForMonth -MonthId $monthId -Destination $d) {
            $destCards += @"
<a class="wp-destination-experience-card" href="../destinations/$($d.id)">
  <img class="wp-destination-experience-image" src="../$($d.hero_image)" alt="$(ConvertTo-HtmlSafe $d.name)"$(Get-ImageDimAttrs $d.hero_image) loading="lazy" decoding="async">
  <div class="wp-destination-experience-content">
    <span class="wp-destination-experience-label">$(ConvertTo-HtmlSafe $d.province)</span>
    <h3>$(ConvertTo-HtmlSafe $d.name)</h3>
    <p>$(ConvertTo-HtmlSafe $d.hero_description)</p>
    <span class="wp-destination-experience-link">Explore &rarr;</span>
  </div>
</a>
"@
        }
    }
    if ($destCards.Count -eq 0) { $destCards = @("<p>Destination guides for this month are coming soon.</p>") }

    # Tours: seeded shuffle for variety across month pages (all tours run all-year)
    # page_url is a clean (extensionless) URL -- the physical file on disk is
    # still <path>.html, so check both before excluding a tour from the pool.
    $tourPool = @($tours | Where-Object {
        if (-not $_.page_url) { return $false }
        $relPath = $_.page_url -replace '^\.\./',''
        $fullPath = Join-Path $root $relPath
        (Test-Path $fullPath) -or (Test-Path "$fullPath.html")
    })
    $tourCards = @()
    if ($tourPool.Count -gt 0) {
        $seedBytes = [System.Text.Encoding]::UTF8.GetBytes("month-$monthId")
        $seed = [System.BitConverter]::ToInt32(([System.Security.Cryptography.MD5]::Create().ComputeHash($seedBytes)), 0)
        $rng = New-Object System.Random($seed)
        $picked = @($tourPool | Sort-Object { $rng.Next() } | Select-Object -First 6)
        foreach ($t in $picked) {
            $tourCards += @"
<a class="wp-destination-experience-card" href="$($t.page_url)">
  <img class="wp-destination-experience-image" src="../$($t.image)" alt="$(ConvertTo-HtmlSafe $t.name)"$(Get-ImageDimAttrs $t.image) loading="lazy" decoding="async">
  <div class="wp-destination-experience-content">
    <span class="wp-destination-experience-label">$(ConvertTo-HtmlSafe $t.category)</span>
    <h3>$(ConvertTo-HtmlSafe $t.name)</h3>
    <p>$(ConvertTo-HtmlSafe $t.description)</p>
    <span class="wp-destination-experience-link">View Experience &rarr;</span>
  </div>
</a>
"@
        }
    }
    if ($tourCards.Count -eq 0) { $tourCards = @("<p>Tour recommendations for this month are coming soon.</p>") }

    # Articles tagged directly with this month or its season group
    $articleCards = @()
    foreach ($a in $articles) {
        $ids = @($a.season_ids)
        if (($ids -contains $monthId) -or ($group -and $ids -contains $group)) {
            $articleImg = if ($a.image_top -and (Test-Path (Join-Path $root $a.image_top))) { $a.image_top } else { $heroImage }
            $articleCategory = if ($a.category) { $a.category } else { "Travel Guide" }
            $articleCards += @"
<a class="wp-destination-experience-card" href="../blog/$($a.slug)">
  <img class="wp-destination-experience-image" src="../$articleImg" alt="$(ConvertTo-HtmlSafe $a.image_top_alt)"$(Get-ImageDimAttrs $articleImg) loading="lazy" decoding="async">
  <div class="wp-destination-experience-content">
    <span class="wp-destination-experience-label">$(ConvertTo-HtmlSafe $articleCategory)</span>
    <h3>$(ConvertTo-HtmlSafe $a.title)</h3>
    <p>$(ConvertTo-HtmlSafe $a.excerpt)</p>
    <span class="wp-destination-experience-link">Read Article &rarr;</span>
  </div>
</a>
"@
        }
    }
    if ($articleCards.Count -eq 0) {
        $articleCards = @("<a class=`"wp-destination-experience-card`" href=`"../Blogs.html`"><div class=`"wp-destination-experience-content`"><span class=`"wp-destination-experience-label`">Insider Guide</span><h3>Explore our Travel Blog</h3><p>Real traveler questions about Costa Rica, answered by the local team.</p><span class=`"wp-destination-experience-link`">Read Articles &rarr;</span></div></a>")
    }

    $prevIdx = ($i - 1 + 12) % 12
    $nextIdx = ($i + 1) % 12
    $prevId = $monthOrder[$prevIdx]
    $nextId = $monthOrder[$nextIdx]
    $prevName = ($monthEntries | Where-Object { $_.id -eq $prevId } | Select-Object -First 1).name
    $nextName = ($monthEntries | Where-Object { $_.id -eq $nextId } | Select-Object -First 1).name

    $heroDescription = "Weather, best destinations and recommended tours for visiting Costa Rica's Guanacaste and Arenal regions in $monthName."
    $cta = $ctaTemplate.Replace('__DESTINATION_NAME__', "Costa Rica in $monthName").Replace('__CTA_URL__', "https://wa.me/50688566325?text=$([Uri]::EscapeDataString("Hello Wild Papagayo! I am planning a trip in $monthName and would love local advice."))")
    $schemaObj = [ordered]@{
        '@context'='https://schema.org'; '@type'='Article'
        headline="Costa Rica in $monthName - Travel Guide"
        description=$weatherBody[$monthId]; url=$canonical
        image=@("$siteUrl/$heroImage")
        datePublished='2026-01-01T00:00:00Z'; dateModified='2026-01-01T00:00:00Z'
        author=@{'@type'='Organization';name='Wild Papagayo';url=$siteUrl}
        publisher=@{'@type'='Organization';'@id'="$siteUrl/#organization";name='Wild Papagayo';logo=@{'@type'='ImageObject';url="$siteUrl/images/logo-wildpapagayo-nav.webp";width=450;height=300}}
    }
    $schema = $schemaObj | ConvertTo-Json -Depth 10 -Compress

    $html = $template.Replace('__COMPONENT_HEADER__', $header).Replace('__COMPONENT_FOOTER__', $footer).Replace('__COMPONENT_CTA__', $cta)
    $replacements = @{
        '__SEO_TITLE__'         = "Costa Rica in $monthName - Weather, Tours & Where to Go | Wild Papagayo"
        '__SEO_DESCRIPTION__'   = Get-SeoDescription $weatherBody[$monthId]
        '__CANONICAL__'         = $canonical
        '__SCHEMA__'            = $schema
        '__HERO_IMAGE__'        = $heroImage
        '__MONTH_NAME__'        = $monthName
        '__HERO_DESCRIPTION__'  = $heroDescription
        '__WEATHER_BODY__'      = [string]$weatherBody[$monthId]
        '__QUICK_FACTS__'       = ($quickFacts -join "`n")
        '__DESTINATION_CARDS__' = ($destCards -join "`n")
        '__TOUR_CARDS__'        = ($tourCards -join "`n")
        '__ARTICLE_CARDS__'     = ($articleCards -join "`n")
        '__PREV_MONTH__'        = $prevId
        '__PREV_MONTH_NAME__'   = $prevName
        '__NEXT_MONTH__'        = $nextId
        '__NEXT_MONTH_NAME__'   = $nextName
    }
    foreach ($key in $replacements.Keys) { $html = $html.Replace($key, $replacements[$key]) }
    $out = Join-Path $outputDir "$monthId.html"
    Write-FileIfChanged -Path $out -Content $html
    Write-Host "Generated month: months/$monthId.html"
    $generated++
}
Write-Host "Month Engine complete: $generated page(s)."

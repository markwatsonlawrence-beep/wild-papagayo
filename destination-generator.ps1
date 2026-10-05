# Wild Engine - Destination Engine MVP
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
$templatePath = Join-Path $root "templates/destination.html"
$destinationsDir = Join-Path $root "knowledge/destinations"
$outputDir = Join-Path $root "destinations"
$blogPath = Join-Path $root "blog-data.json"
$toursPath = Join-Path $root "knowledge/tours.json"
$airportsPath = Join-Path $root "knowledge/airports.json"
$siteUrl = "https://wildpapagayo.com"

if (-not (Test-Path $templatePath)) { throw "Missing template: $templatePath" }
if (-not (Test-Path $destinationsDir)) { throw "Missing destination data: $destinationsDir" }
New-Item -ItemType Directory -Force $outputDir | Out-Null

function Read-Utf8Json([string]$path) {
  return ([System.IO.File]::ReadAllText($path) | ConvertFrom-Json)
}
function ConvertTo-HtmlSafe([object]$value) { return [System.Net.WebUtility]::HtmlEncode([string]$value) }

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
function Component([string]$name) {
  $p = Join-Path $root "templates/components/$name.html"
  if (-not (Test-Path $p)) { throw "Missing component: $p" }
  return [System.IO.File]::ReadAllText($p)
}

$template = [System.IO.File]::ReadAllText($templatePath)
$header = Component "header"
$footer = Component "footer"
$ctaTemplate = Component "cta"
$articles = if (Test-Path $blogPath) { @(Read-Utf8Json $blogPath) } else { @() }
$tours = if (Test-Path $toursPath) { @(Read-Utf8Json $toursPath) } else { @() }
$airports = if (Test-Path $airportsPath) { @(Read-Utf8Json $airportsPath) } else { @() }
$masterHotelsDir = Join-Path $root 'knowledge\master\hotels'
$hotels = @()
if (Test-Path $masterHotelsDir) {
    $hotels = Get-ChildItem $masterHotelsDir -Filter '*.json' -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' } | ForEach-Object {
        $h = Read-Utf8Json $_.FullName
        # Strict publication gate: this loader reads knowledge/master/hotels, whose
        # publication field is workflow.status. Only "published" hotels may be shown
        # or linked from a destination page (draft, disabled, missing or unknown => excluded).
        if ([string]$h.workflow.status -ne 'published') { return }
        [pscustomobject]@{
            id = $_.BaseName
            name = if ($h.identity.display_name) { [string]$h.identity.display_name } else { [string]$h.identity.official_name }
            destination_id = [string]$h.location.destination_id
            category = [string]$h.identity.category
            hero_image = [string]$h.gallery.hero_image
            hero_image_alt = [string]$h.gallery.hero_image_alt
            hero_description = [string]$h.editorial.hero_description
        }
    }
}

function Find-EntityById([object[]]$items, [string]$id) {
  if (-not $id) { return $null }
  return $items | Where-Object { $_.id -eq $id } | Select-Object -First 1
}

# Strict publication gate: a destination is public only when its record says
# status "published". Missing, "draft", "disabled" or unknown => not public, so it
# gets no page and is never linked from another destination page.
function Test-DestinationPublished([string]$Id) {
  $f = Join-Path $destinationsDir "$Id.json"
  if (-not (Test-Path $f)) { return $false }
  return ([string](Read-Utf8Json $f).status -eq 'published')
}
$destinationFiles = Get-ChildItem $destinationsDir -Filter *.json | Sort-Object Name

foreach ($file in $destinationFiles) {
  $d = Read-Utf8Json $file.FullName
  if ([string]$d.status -ne 'published') { continue }
  foreach ($required in @('id','name','hero_image','description')) {
    if (-not $d.$required) { throw "$($file.Name): missing required field '$required'" }
  }
  $canonical = "$siteUrl/destinations/$($d.id)"

  # Resolve airport from the Knowledge Graph. The legacy airport string remains a fallback.
  $airport = Find-EntityById $airports ([string]$d.airport_id)
  $airportDisplay = if ($airport) {
    "$($airport.name) ($($airport.iata))"
  } elseif ($d.airport) {
    [string]$d.airport
  } else {
    "To be confirmed"
  }

  $quickFacts = @(
    @{Label='Nearest airport';Value=$airportDisplay},
    @{Label='Transfer time';Value=$d.transfer_time},
    @{Label='Best season';Value=$d.best_season},
    @{Label='Province';Value=$d.province}
  ) | ForEach-Object { "<div class=`"destination-fact`"><small>$(ConvertTo-HtmlSafe ($_.Label))</small><strong>$(ConvertTo-HtmlSafe ($_.Value))</strong></div>" }

  $bestFor = @($d.best_for) | ForEach-Object { "<span class=`"destination-pill`">$(ConvertTo-HtmlSafe $_)</span>" }

  # Rich destination body — Why visit / highlights / considerations / FAQ
  $whyParas = if ($d.why_visit -and $d.why_visit.Count -gt 0) {
    ($d.why_visit | ForEach-Object { "<p>$(ConvertTo-HtmlSafe $_)</p>" }) -join ""
  } else { "<p>$(ConvertTo-HtmlSafe $d.description)</p>" }
  $highlightsHtml = ""
  if ($d.highlights -and $d.highlights.Count -gt 0) {
    $items = ($d.highlights | ForEach-Object { "<li>$(ConvertTo-HtmlSafe $_)</li>" }) -join ""
    $highlightsHtml = "<h3>What travelers usually like</h3><ul class=`"destination-list destination-list--pro`">$items</ul>"
  }
  $considerationsHtml = ""
  if ($d.considerations -and $d.considerations.Count -gt 0) {
    $items = ($d.considerations | ForEach-Object { "<li>$(ConvertTo-HtmlSafe $_)</li>" }) -join ""
    $considerationsHtml = "<h3>Things to consider</h3><ul class=`"destination-list destination-list--con`">$items</ul>"
  }
  $faqHtml = ""
  if ($d.faq -and $d.faq.Count -gt 0) {
    $faqs = ($d.faq | ForEach-Object { "<div class=`"destination-faq-item`"><h3>$(ConvertTo-HtmlSafe $_.q)</h3><p>$(ConvertTo-HtmlSafe $_.a)</p></div>" }) -join ""
    $faqHtml = "<section class=`"destination-body-section`"><h2>Frequently asked questions</h2><div class=`"destination-faq`">$faqs</div></section>"
  }
  $colsHtml = if ($highlightsHtml -or $considerationsHtml) {
    "<div class=`"destination-why-cols`">$highlightsHtml$considerationsHtml</div>"
  } else { "" }
  $destinationBody = "<section class=`"destination-body-section`"><h2>Why visit $($d.name)?</h2>$whyParas<div class=`"destination-pills`">$($bestFor -join '')</div>$colsHtml</section>$faqHtml"
  $tourCards = @()
  $itineraryTours = @()
  foreach ($tourId in @($d.featured_tours)) {
    $tour = Find-EntityById $tours ([string]$tourId)
    $tourFile = Join-Path $root "tours/$tourId.html"
    if (Test-Path $tourFile) {
      $tourName = if ($tour -and $tour.name) { $tour.name } else { ($tourId -replace '-', ' ') }
      $image = if ($tour -and $tour.image) { $tour.image } else { $d.hero_image }
      $category = if ($tour -and $tour.category) { $tour.category } else { "Curated Experience" }
      $description = if ($tour -and $tour.description) { $tour.description } else { "Explore this experience from $($d.name) with private transportation and local support." }
      $tourHref = if ($tour -and $tour.page_url) { [string]$tour.page_url } else { "../tours/$tourId" }
      $tourCards += @"
<a class="wp-destination-experience-card" href="$tourHref">
  <img class="wp-destination-experience-image" src="../$image" alt="$(ConvertTo-HtmlSafe $tourName)"$(Get-ImageDimAttrs $image) loading="lazy" decoding="async">
  <div class="wp-destination-experience-content">
    <span class="wp-destination-experience-label">$(ConvertTo-HtmlSafe $category)</span>
    <h3>$(ConvertTo-HtmlSafe $tourName)</h3>
    <p>$(ConvertTo-HtmlSafe $description)</p>
    <span class="wp-destination-experience-link">View Experience &rarr;</span>
  </div>
</a>
"@
      $itineraryTours += [pscustomobject]@{ name = $tourName; description = $description }
    }
  }
  if ($tourCards.Count -eq 0) { $tourCards = @("<p>More curated experiences will be added soon.</p>") }

  # ── Travel Score + Destination DNA: Claude-assisted, grounded scores from
  #    destination-experience-scorer.ps1. Only rendered when the field exists --
  #    destinations not yet scored show nothing here. DNA tags are a pure
  #    derivation of the same scores (top-scoring categories -> adjective),
  #    no extra API call needed. ──
  $travelScoreSection = ""
  $dnaSection = ""
  $difficultyBadge = ""
  $scoreCategories = @('adventure', 'families', 'private', 'nightlife', 'restaurants', 'beach', 'wildlife', 'relaxation')
  $dnaLabels = @{
    adventure = 'Adventure'; families = 'Family-Friendly'; private = 'Private'; nightlife = 'Energetic'
    restaurants = 'Foodie'; beach = 'Beach'; wildlife = 'Wildlife-Rich'; relaxation = 'Relaxing'
  }
  if ($d.experience_scores) {
    $scoreRows = @()
    $dnaScored = @()
    foreach ($catName in $scoreCategories) {
      $prop = $d.experience_scores.PSObject.Properties[$catName]
      if (-not $prop) { continue }
      $catScore = [int]$prop.Value.score
      $catReason = [string]$prop.Value.reason
      $filled = ('&#9733;' * $catScore)
      $empty = ('&#9734;' * (5 - $catScore))
      $reasonHtml = if ($catReason) { "<p>$(ConvertTo-HtmlSafe $catReason)</p>" } else { "" }
      $scoreRows += "<div class=`"destination-score-card`"><div class=`"destination-score-head`"><strong>$(ConvertTo-HtmlSafe ($catName -replace '_',' '))</strong><span class=`"destination-score-stars`"><span class=`"filled`">$filled</span>$empty</span></div>$reasonHtml</div>"
      $dnaScored += [pscustomobject]@{ label = $dnaLabels[$catName]; score = $catScore }
    }
    $dnaTop = @($dnaScored | Where-Object { $_.score -ge 4 } | Sort-Object score -Descending | Select-Object -First 5)
    if ($dnaTop.Count -gt 0) {
      $dnaPills = ($dnaTop | ForEach-Object { "<span class=`"destination-pill`">$(ConvertTo-HtmlSafe $_.label)</span>" }) -join ""
      $dnaSection = "<div class=`"destination-dna`"><span class=`"blog-best-for-label`" style=`"display:block;margin-bottom:8px`">Destination DNA</span><div class=`"destination-pills`">$dnaPills</div></div>"
    }
    $difficultyProp = $d.experience_scores.PSObject.Properties['difficulty']
    if ($difficultyProp) {
      $diffLevel = [string]$difficultyProp.Value.level
      $diffReason = [string]$difficultyProp.Value.reason
      $difficultyBadge = "<div class=`"destination-fact`" title=`"$(ConvertTo-HtmlSafe $diffReason)`"><small>Travel Difficulty</small><strong>$(ConvertTo-HtmlSafe $diffLevel)</strong></div>"
      $quickFacts = @($quickFacts) + $difficultyBadge
    }
    $travelScoreSection = "<section class=`"destination-section`"><h2>Travel Score</h2><div class=`"destination-score-grid`">$($scoreRows -join "`n")</div></section>"
  }

  # ── Restaurants: real, live-sourced from Google Places (restaurant-finder.ps1).
  #    Only rendered when present. ──
  $restaurantsSection = ""
  if ($d.restaurants -and @($d.restaurants).Count -gt 0) {
    $sortedRestaurants = @($d.restaurants | Sort-Object -Property @{Expression={[double]$_.rating}; Descending=$true}, @{Expression={[int]$_.review_count}; Descending=$true})
    $restaurantCards = @($sortedRestaurants | ForEach-Object {
      $cuisineTag = if (@($_.types).Count -gt 0) { (@($_.types)[0] -replace '_',' ') } else { 'Restaurant' }
      $ratingText = ([double]$_.rating).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
      "<div class=`"destination-restaurant-card`"><span class=`"destination-restaurant-cuisine`">$(ConvertTo-HtmlSafe $cuisineTag)</span><h3>$(ConvertTo-HtmlSafe $_.name)</h3><div class=`"destination-restaurant-rating`">&#9733; $ratingText <small>($(ConvertTo-HtmlSafe $_.review_count) reviews)</small></div><p>$(ConvertTo-HtmlSafe $_.address)</p></div>"
    })
    $restaurantsSection = "<section class=`"destination-section`"><h2>Where to Eat</h2><p style=`"color:#667085;font-size:.82rem;margin:-10px 0 20px`">Sourced live from Google -- ratings and details may change.</p><div class=`"destination-restaurant-grid`">$($restaurantCards -join "`n")</div></section>"
  }

  # ── Wildlife: real, source-grounded species with notes (WebFetch from Wikipedia/park
  #    pages). Only rendered when present -- most destinations don't have this yet. ──
  $wildlifeSection = ""
  if ($d.wildlife -and @($d.wildlife).Count -gt 0) {
    $wildlifeCards = @($d.wildlife | ForEach-Object {
      "<div class=`"destination-wildlife-card`"><h3>$(ConvertTo-HtmlSafe $_.name)</h3><p>$(ConvertTo-HtmlSafe $_.note)</p><small>Source: $(ConvertTo-HtmlSafe $_.source)</small></div>"
    })
    $wildlifeSection = "<section class=`"destination-section`"><h2>Wildlife You May See</h2><div class=`"destination-wildlife-grid`">$($wildlifeCards -join "`n")</div></section>"
  }

  # ── Interactive map: place-name embed, no API key or stored coordinates needed ──
  $mapQuery = [Uri]::EscapeDataString("$($d.name), Costa Rica")
  $interactiveMap = "<iframe src=`"https://www.google.com/maps?q=$mapQuery&output=embed`" loading=`"lazy`" referrerpolicy=`"no-referrer-when-downgrade`" title=`"Map of $(ConvertTo-HtmlSafe $d.name)`"></iframe>"

  # ── Transportation cards: card 1 is informational (real airport data). Cards 2 and 3
  #    each sell one specific Wild Papagayo service and link straight to that service's
  #    own booking form -- guides.html for a local guide, transport.html for a private
  #    transfer -- instead of a single generic "recommended" card. ──
  $transportCards = @(
    "<div class=`"destination-transport-card destination-transport-card--cta`"><small>Nearest Airport</small><strong>$(ConvertTo-HtmlSafe $airportDisplay)</strong><span>The gateway most Wild Papagayo guests use to reach $(ConvertTo-HtmlSafe $d.name).</span></div>"
    "<div class=`"destination-transport-card destination-transport-card--cta`"><small>Book Direct With Us</small><strong>Local Bilingual Guide</strong><span>A local guide who knows $(ConvertTo-HtmlSafe $d.name) turns a day trip into a real experience -- wildlife, history and the spots most visitors miss.</span><a class=`"destination-transport-cta-link`" href=`"../guides#book-guide`">Book a guide &rarr;</a></div>"
    "<div class=`"destination-transport-card destination-transport-card--cta`"><small>Book Direct With Us</small><strong>Private Transfer</strong><span>Skip the rental car -- English-speaking drivers, door-to-door, timed to your flight, approx. $(ConvertTo-HtmlSafe $d.transfer_time) from $(ConvertTo-HtmlSafe $airportDisplay).</span><a class=`"destination-transport-cta-link`" href=`"../transport#booking-form`">Book a transfer &rarr;</a></div>"
  )

  $hotelCards = @()
  foreach ($hotel in @($hotels | Where-Object { $_.destination_id -eq $d.id })) {
    $hotelImage = if ($hotel.hero_image) { $hotel.hero_image } else { $d.hero_image }
    $hotelDesc = if ($hotel.hero_description) { $hotel.hero_description } else { "Stay at $($hotel.name) with easy access to $($d.name)." }
    $hotelCards += @"
<a class="wp-destination-experience-card" href="../hotels/$($hotel.id)">
  <img class="wp-destination-experience-image" src="../$hotelImage" alt="$(ConvertTo-HtmlSafe $hotel.hero_image_alt)"$(Get-ImageDimAttrs $hotelImage) loading="lazy" decoding="async">
  <div class="wp-destination-experience-content">
    <span class="wp-destination-experience-label">$(ConvertTo-HtmlSafe $hotel.category)</span>
    <h3>$(ConvertTo-HtmlSafe $hotel.name)</h3>
    <p>$(ConvertTo-HtmlSafe $hotelDesc)</p>
    <span class="wp-destination-experience-link">View Hotel &rarr;</span>
  </div>
</a>
"@
  }
  $hasDirectHotels = $hotelCards.Count -gt 0
  # Rendered below only when there are direct hotels to show; the region-overview case
  # (no direct hotels) gets the "Where to Stay in X" sub-destination cards instead, built
  # further down alongside $itinerarySection -- showing both would just duplicate an
  # empty "Where to stay" heading right above a populated one.
  $whereToStaySection = if ($hasDirectHotels) { "<section class=`"destination-section`"><h2>Where to stay</h2><div class=`"destination-grid`">$($hotelCards -join "`n")</div></section>" } else { "" }

  # ── "A sample itinerary" only makes sense for a destination with its own hotels to
  #    arrive at and stay in (Papagayo, Playa Hermosa...). For a region-overview page
  #    with no directly-linked hotels (e.g. Guanacaste), swap it for real internal links
  #    to the sub-destinations that do have hotels -- more useful and more honest than
  #    a generic "your hotel in Guanacaste" itinerary. ──
  $itinerarySection = ""
  if ($hasDirectHotels) {
    $itineraryDays = New-Object System.Collections.Generic.List[string]
    $itineraryDays.Add("<div class=`"destination-itin-day`"><div class=`"destination-itin-day-num`">DAY&nbsp;1</div><div class=`"destination-itin-day-body`"><h4>Arrival &amp; Private Transfer</h4><p>Private transfer from $(ConvertTo-HtmlSafe $airportDisplay) to your hotel in $(ConvertTo-HtmlSafe $d.name) (approx. $(ConvertTo-HtmlSafe $d.transfer_time)). Settle in and relax.</p></div></div>")
    $dayNum = 2
    foreach ($it in ($itineraryTours | Select-Object -First 3)) {
      $itineraryDays.Add("<div class=`"destination-itin-day`"><div class=`"destination-itin-day-num`">DAY&nbsp;$dayNum</div><div class=`"destination-itin-day-body`"><h4>$(ConvertTo-HtmlSafe $it.name)</h4><p>$(ConvertTo-HtmlSafe $it.description)</p></div></div>")
      $dayNum++
    }
    $itineraryDays.Add("<div class=`"destination-itin-day`"><div class=`"destination-itin-day-num`">DAY&nbsp;$dayNum</div><div class=`"destination-itin-day-body`"><h4>Departure</h4><p>Private transfer back to $(ConvertTo-HtmlSafe $airportDisplay), timed to your flight.</p></div></div>")
    $suggestedItinerary = $itineraryDays.ToArray() -join "`n"
    $itinerarySection = "<section class=`"destination-section`"><h2>A sample itinerary</h2><div class=`"destination-itinerary`">$suggestedItinerary</div><p class=`"destination-itin-note`">A starting point, not a fixed plan -- every Wild Papagayo trip is customized to you.</p></section>"
  } elseif ($null -ne $d.stay_bases -and @($d.stay_bases).Count -gt 0) {
    # Explicit, curated lodging-base list -- semantically separate from `nearby` (which still
    # drives the unrelated "Nearby destinations" links section further below) and NOT filtered
    # by hotel-mapping presence, unlike the legacy `nearby` fallback below. This exists because
    # the legacy path conflates "has a Wild Papagayo-mapped hotel" with "is a legitimate lodging
    # base" -- e.g. it silently drops a real beach town with no mapped hotel, and can surface an
    # excursion destination purely because a hotel happens to be tagged with it. A destination
    # only takes this path if it explicitly opts in via `stay_bases`; every other destination page
    # is unaffected and keeps the exact legacy behavior below.
    $stayCards = New-Object System.Collections.Generic.List[string]
    $stayTableRows = New-Object System.Collections.Generic.List[string]
    $stayRowIndex = 0
    foreach ($sb in @($d.stay_bases)) {
      $sbId = [string]$sb.id
      $nearFile = Join-Path $destinationsDir "$sbId.json"
      if (-not (Test-DestinationPublished $sbId)) { continue }
      $near = Read-Utf8Json $nearFile
      $nearImg = if ($near.hero_image) { [string]$near.hero_image } else { [string]$d.hero_image }
      $nearBestFor = @($near.best_for) | Select-Object -First 3
      $tagsHtml = ($nearBestFor | ForEach-Object { "<span class=`"destination-stay-tag`">$(ConvertTo-HtmlSafe $_)</span>" }) -join ""
      $stayCards.Add("<a class=`"dg-guide-card`" href=`"$sbId`"><div class=`"dg-guide-img`"><img src=`"../$nearImg`" alt=`"$(ConvertTo-HtmlSafe $near.name)`"$(Get-ImageDimAttrs $nearImg) loading=`"lazy`" decoding=`"async`"></div><div><h3>$(ConvertTo-HtmlSafe $near.name)</h3><p>$(ConvertTo-HtmlSafe $near.hero_description)</p><div class=`"destination-stay-tags`">$tagsHtml</div></div></a>")
      $bestForText = (@($near.best_for) | Select-Object -First 2) -join ", "
      $rowStyle = if ($stayRowIndex % 2 -eq 1) { " style=`"background:#f8f5ef;`"" } else { "" }
      $stayTableRows.Add("<tr$rowStyle><td style=`"padding:10px 14px;`"><strong>$(ConvertTo-HtmlSafe $near.name)</strong></td><td style=`"padding:10px 14px;`">$(ConvertTo-HtmlSafe $bestForText)</td><td style=`"padding:10px 14px;`">$(ConvertTo-HtmlSafe $near.transfer_time)</td><td style=`"padding:10px 14px;`">$(ConvertTo-HtmlSafe $sb.without_car_note)</td></tr>")
      $stayRowIndex++
    }
    if ($stayCards.Count -gt 0) {
      $stayTableHtml = "<div style=`"overflow-x:auto;margin:20px 0;`"><table style=`"width:100%;border-collapse:collapse;font-size:.92rem;`"><thead><tr style=`"background:#062448;color:#fff;`"><th style=`"padding:10px 14px;text-align:left;`">Area</th><th style=`"padding:10px 14px;text-align:left;`">Best For</th><th style=`"padding:10px 14px;text-align:left;`">From LIR</th><th style=`"padding:10px 14px;text-align:left;`">Without a Car</th></tr></thead><tbody>$($stayTableRows.ToArray() -join "`n")</tbody></table></div>"
      $itinerarySection = "<section class=`"destination-section`"><h2>Where to Stay in $(ConvertTo-HtmlSafe $d.name)</h2><p>$(ConvertTo-HtmlSafe $d.name) covers several distinct beach areas, each with its own character -- choose your base based on your priorities. Day trips like Rincon de la Vieja are easy to reach from any of these bases, so you don't need to stay there to visit them.</p><div class=`"destination-grid`">$($stayCards.ToArray() -join "`n")</div>$stayTableHtml</section>"
    }
  } elseif (@($d.nearby).Count -gt 0) {
    $stayCards = @($d.nearby) | ForEach-Object {
      $nearFile = Join-Path $destinationsDir "$_.json"
      if (-not (Test-DestinationPublished ([string]$_))) { return }
      $near = Read-Utf8Json $nearFile
      $nearHotelCount = @($hotels | Where-Object { $_.destination_id -eq $near.id }).Count
      if ($nearHotelCount -eq 0) { return }
      $nearImg = if ($near.hero_image) { [string]$near.hero_image } else { [string]$d.hero_image }
      $nearBestFor = @($near.best_for) | Select-Object -First 3
      $tagsHtml = ($nearBestFor | ForEach-Object { "<span class=`"destination-stay-tag`">$(ConvertTo-HtmlSafe $_)</span>" }) -join ""
      "<a class=`"dg-guide-card`" href=`"$_`"><div class=`"dg-guide-img`"><img src=`"../$nearImg`" alt=`"$(ConvertTo-HtmlSafe $near.name)`"$(Get-ImageDimAttrs $nearImg) loading=`"lazy`" decoding=`"async`"></div><div><h3>$(ConvertTo-HtmlSafe $near.name)</h3><p>$(ConvertTo-HtmlSafe $near.hero_description)</p><div class=`"destination-stay-tags`">$tagsHtml</div></div></a>"
    }
    $stayCards = @($stayCards | Where-Object { $_ })
    if ($stayCards.Count -gt 0) {
      $itinerarySection = "<section class=`"destination-section`"><h2>Where to Stay in $(ConvertTo-HtmlSafe $d.name)</h2><p>$(ConvertTo-HtmlSafe $d.name) covers several distinct areas, each with its own hotels and character. Here's where our guests actually stay:</p><div class=`"destination-grid`">$($stayCards -join "`n")</div></section>"
    }
  }

  $articleCards = @()
  foreach ($a in $articles) {
    # Strict publication gate: only status "published" may get a card (missing,
    # draft, disabled or unknown => excluded). Ranking/order/cap unchanged.
    if ([string]$a.status -ne 'published') { continue }
    $ids = @($a.destinations) + @($a.destination_ids)
    if ($ids -contains $d.id) {
      $articleImg = if ($a.image_top -and (Test-Path (Join-Path $root $a.image_top))) { $a.image_top } else { $d.hero_image }
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
  if ($articleCards.Count -eq 0) { $articleCards = @("<a class=`"wp-destination-experience-card`" href=`"../Blogs`"><div class=`"wp-destination-experience-content`"><span class=`"wp-destination-experience-label`">Insider Guide</span><h3>Explore our Travel Blog</h3><p>Read practical advice and destination guides from our local team.</p><span class=`"wp-destination-experience-link`">Read Articles &rarr;</span></div></a>") }

  $nearbyLinks = @($d.nearby) | ForEach-Object {
    $nearFile = Join-Path $destinationsDir "$_.json"
    if (Test-DestinationPublished ([string]$_)) {
      $near = Read-Utf8Json $nearFile
      $nearImg = if ($near.hero_image) { [string]$near.hero_image } else { [string]$d.hero_image }
      $nearDesc = if ($near.hero_description) { [string]$near.hero_description } else { [string]$near.description }
      "<a class=`"dg-guide-card`" href=`"$_`"><div class=`"dg-guide-img`"><img src=`"../$nearImg`" alt=`"$(ConvertTo-HtmlSafe $near.name)`"$(Get-ImageDimAttrs $nearImg) loading=`"lazy`" decoding=`"async`"></div><div><h3>$(ConvertTo-HtmlSafe $near.name)</h3><p>$(ConvertTo-HtmlSafe $nearDesc)</p></div></a>"
    }
    # A nearby id with no record, or a record that is not published, gets no card
    # (previously a dead-href text card was rendered for a missing record).
  }

  $cta = $ctaTemplate.Replace('__DESTINATION_NAME__', [string]$d.name).Replace('__CTA_URL__', "https://wa.me/50688566325?text=$([Uri]::EscapeDataString("Hello Wild Papagayo! I am planning a trip to $($d.name) and would love local help."))")
  $touristDestination = [ordered]@{'@type'='TouristDestination';name=$d.name;description=$d.description;url=$canonical;image="$siteUrl/$($d.hero_image)"}
  # Links this page (not the destination itself) to the single site-wide
  # Wild Papagayo organization node, same pattern used on hotel/tour pages.
  $destWebPage = @{'@type'='WebPage';'@id'="$canonical#webpage";url=$canonical;name=[string]$d.name;publisher=@{'@type'='TravelAgency';'@id'="$siteUrl/#organization";name='Wild Papagayo'}}
  $destBreadcrumb = @{'@type'='BreadcrumbList';itemListElement=@(@{'@type'='ListItem';position=1;name='Home';item="$siteUrl/"},@{'@type'='ListItem';position=2;name='Destinations';item="$siteUrl/destinations/"},@{'@type'='ListItem';position=3;name=[string]$d.name;item=$canonical})}
  $schemaGraph = @($touristDestination, $destWebPage, $destBreadcrumb)
  if ($d.faq -and $d.faq.Count -gt 0) {
    $faqEntities = @($d.faq | ForEach-Object { @{'@type'='Question';name=[string]$_.q;acceptedAnswer=@{'@type'='Answer';text=[string]$_.a}} })
    $schemaGraph += @{'@type'='FAQPage';mainEntity=$faqEntities}
  }
  $schema = (@{'@context'='https://schema.org';'@graph'=$schemaGraph} | ConvertTo-Json -Depth 10 -Compress)
  $photoGallery = ""
  if ($d.gallery -and $d.gallery.Count -gt 0) {
    $galleryImgs = ($d.gallery | ForEach-Object { '<div class="destination-gallery-img"><img src="../' + [string]$_.src + '" alt="' + (ConvertTo-HtmlSafe $_.alt) + '"' + (Get-ImageDimAttrs $_.src) + ' loading="lazy" decoding="async"></div>' }) -join ''
    $photoGallery = '<div class="destination-gallery">' + $galleryImgs + '</div>'
  }

  $testimonialsSection = ""
  if ($d.testimonials -and $d.testimonials.Count -gt 0) {
    $tCards = ($d.testimonials | ForEach-Object {
      $initial = if ($_.author) { ([string]$_.author).Substring(0,1) } else { 'W' }
      $locationSpan = if ($_.location) { '<span>' + (ConvertTo-HtmlSafe $_.location) + '</span>' } else { '' }
      '<article class="testimonial-card reveal"><div class="testimonial-stars">&#9733;&#9733;&#9733;&#9733;&#9733;</div><blockquote>' + (ConvertTo-HtmlSafe $_.quote) + '</blockquote><div class="testimonial-author"><div class="rev-avatar">' + $initial + '</div><div><strong>' + (ConvertTo-HtmlSafe $_.author) + '</strong>' + $locationSpan + '</div></div></article>'
    }) -join ''
    $testimonialsSection = '<section class="section testimonials-section" style="padding:60px 0;"><div class="container"><div class="section-head reveal"><span class="section-kicker">Traveler Stories</span><h2 class="section-title">What Travelers Say About ' + (ConvertTo-HtmlSafe $d.name) + '</h2></div><div class="testimonials-grid">' + $tCards + '</div></div></section>'
  }
  $html = $template.Replace('__COMPONENT_HEADER__',$header).Replace('__COMPONENT_FOOTER__',$footer).Replace('__COMPONENT_CTA__',$cta)
  $replacements = @{
    '__SEO_TITLE__' = "$($d.name) Travel Guide | Wild Papagayo"
    '__SEO_DESCRIPTION__' = Get-SeoDescription ([string]$d.description)
    '__CANONICAL__' = $canonical
    '__OG_IMAGE__' = "$siteUrl/$($d.hero_image)"
    '__SCHEMA__' = $schema
    '__HERO_IMAGE__' = [string]$d.hero_image
    '__PHOTO_GALLERY__' = $photoGallery
    '__DESTINATION_NAME__' = [string]$d.name
    '__HERO_DESCRIPTION__' = [string]$d.hero_description
    '__DESTINATION_BODY__' = $destinationBody
    '__QUICK_FACTS__' = ($quickFacts -join "`n")
    '__WHERE_TO_STAY_SECTION__' = $whereToStaySection
    '__TOUR_CARDS__' = ($tourCards -join "`n")
    '__ARTICLE_CARDS__' = ($articleCards -join "`n")
    '__NEARBY_LINKS__' = ($nearbyLinks -join "`n")
    '__TESTIMONIALS_SECTION__' = $testimonialsSection
    '__TRAVEL_SCORE_SECTION__' = $travelScoreSection
    '__DNA_SECTION__' = $dnaSection
    '__INTERACTIVE_MAP__' = $interactiveMap
    '__TRANSPORTATION_CARDS__' = ($transportCards -join "`n")
    '__ITINERARY_SECTION__' = $itinerarySection
    '__WILDLIFE_SECTION__' = $wildlifeSection
    '__RESTAURANTS_SECTION__' = $restaurantsSection
  }
  foreach ($key in $replacements.Keys) { $html = $html.Replace($key, $replacements[$key]) }
  $out = Join-Path $outputDir "$($d.id).html"
  Write-FileIfChanged -Path $out -Content $html
  Write-Host "Generated destination: destinations/$($d.id).html"
}
Write-Host "Destination Engine complete: $($destinationFiles.Count) page(s)."

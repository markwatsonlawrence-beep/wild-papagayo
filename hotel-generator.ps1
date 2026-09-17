# ============================================================
# Wild Papagayo - Premium Hotel Engine v2.0
# Generates premium static hotel guide pages from knowledge/hotels/*.json
# Uses the Recommendation Engine output when available.
# Compatible with Windows PowerShell 5.1.
# Usage: .\hotel-generator.ps1
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

$root = $PSScriptRoot
$hotelDir = Join-Path $root "knowledge\hotels"
$destinationDir = Join-Path $root "knowledge\destinations"
$tourDir = Join-Path $root "knowledge\tours"
$airportsPath = Join-Path $root "knowledge\airports.json"
$recommendationsPath = Join-Path $root "knowledge\recommendations.json"
$blogPath = Join-Path $root "blog-data.json"
$headerPath = Join-Path $root "templates\components\header.html"
$footerPath = Join-Path $root "templates\components\footer.html"
$outDir = Join-Path $root "hotels"
$siteUrl = "https://wildpapagayo.com"

New-Item -ItemType Directory -Force $outDir | Out-Null

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Missing required file: $Path" }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}
function ConvertTo-HtmlSafe {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Value.ToString())
}
function Get-PropertyValue {
    param([object]$Object,[string]$Name,[object]$Default=$null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    return $p.Value
}
function Get-ArrayValue {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    return @($Value)
}
function Get-ShortHotelName {
    param([object]$Hotel)
    $brand = [string](Get-PropertyValue $Hotel "brand" "")
    if (-not [string]::IsNullOrWhiteSpace($brand)) { return $brand }
    return [string]$Hotel.name
}
function Get-IconHtml {
    param([string]$Name)
    $key = ($Name.ToLowerInvariant() -replace '[^a-z0-9]','')
    switch -Regex ($key) {
        'airport|flight|arrival|departure' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M22 2 9.5 14.5"/><path d="m16 2 6 0 0 6"/><path d="M14 6 4.5 3.5 2 6l7 5"/><path d="m13 15 5 7 2.5-2.5-2.5-9.5"/></svg>' }
        'location|destination|province' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 10c0 5-8 12-8 12S4 15 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.5"/></svg>' }
        'transfer|car|transport' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m5 17-2 2v2h3l2-2h8l2 2h3v-2l-2-2-2-7H7l-2 7Z"/><path d="M7 10 8.5 6h7L17 10"/><circle cx="7.5" cy="16" r="1"/><circle cx="16.5" cy="16" r="1"/></svg>' }
        'luxury|style|resort|hotel' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m3 8 4-5h10l4 5-9 13L3 8Z"/><path d="m7 3 5 18 5-18M3 8h18"/></svg>' }
        'famil|group' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="9" cy="8" r="3"/><circle cx="17" cy="10" r="2"/><path d="M3 21v-2a6 6 0 0 1 12 0v2M15 16a4 4 0 0 1 6 3v2"/></svg>' }
        'couple|romance|honeymoon' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.6l-1-1a5.5 5.5 0 0 0-7.8 7.8l1 1L12 21l7.8-7.6 1-1a5.5 5.5 0 0 0 0-7.8Z"/></svg>' }
        'wellness|spa' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 22c4-3 6-7 6-11-4 0-7 2-9 5-1-4-4-6-7-6 0 6 4 11 10 12Z"/><path d="M12 22c-1-5 0-10 4-14"/></svg>' }
        'adventure|nature|golf|beach' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m3 20 7-12 4 6 2-3 5 9H3Z"/><path d="m10 8 2-4 2 4"/></svg>' }
        'walk' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="13" cy="4" r="2"/><path d="m10 22 1-7-3-2 2-5 5 3 3 1M16 22l-2-7"/></svg>' }
        'night' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3 7 7 0 0 0 21 12.8Z"/></svg>' }
        'eco|sustainab|green|conscious|responsible' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 21c0-9 4-15 14-16-1 10-7 14-14 16Z"/><path d="M5 21c2-4 5-7 9-9"/></svg>' }
        'food|dining|beer|wine|craft|culinary|foodie|gastro' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M7 2v8a2 2 0 0 0 2 2v10M11 2v10M7 2a2 2 0 0 0-2 2v6M17 2c-2 0-3 2-3 5s1 5 3 5v10"/></svg>' }
        'design|architect' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M9 21V9"/></svg>' }
        'photo|instagram|view|scenic' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="12" cy="12" r="3.5"/><path d="M9 5 10.5 3h3L15 5"/></svg>' }
        'calendar|season|weather|time|month|sun' { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/><path d="m9 15 2 2 4-4"/></svg>' }
        default { return '<svg class="hp-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="m9 12 2 2 4-5"/></svg>' }
    }
}
function Get-GoogleBadgeHtml {
    return '<span class="hp-google-badge" title="Sourced from Google"><svg viewBox="0 0 48 48" aria-hidden="true"><path fill="#4285F4" d="M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17Z"/><path fill="#34A853" d="M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46Z"/><path fill="#FBBC05" d="M11.69 28.18A13.5 13.5 0 0 1 10.98 24c0-1.45.25-2.86.71-4.18v-5.7H4.34A21.99 21.99 0 0 0 2 24c0 3.55.85 6.91 2.34 9.88l7.35-5.7Z"/><path fill="#EA4335" d="M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07Z"/></svg></span>'
}
function Get-StarHtml {
    param([double]$Score)
    $rounded = [Math]::Round($Score)
    if ($rounded -lt 0) { $rounded = 0 }
    if ($rounded -gt 5) { $rounded = 5 }
    $html = '<span class="hp-stars" aria-label="' + $Score.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture) + ' out of 5">'
    for ($i=1; $i -le 5; $i++) {
        $class = if ($i -le $rounded) { 'hp-star is-filled' } else { 'hp-star' }
        $html += '<svg class="' + $class + '" viewBox="0 0 24 24" aria-hidden="true"><path d="m12 2.5 2.9 5.9 6.5.9-4.7 4.6 1.1 6.5-5.8-3.1-5.8 3.1 1.1-6.5-4.7-4.6 6.5-.9L12 2.5Z"/></svg>'
    }
    $html += '</span>'
    return $html
}
function Get-DayImage {
    param([string]$Title, [hashtable]$TourImageByName, [string]$FallbackImage)
    $key = $Title.ToLowerInvariant()
    if ($TourImageByName.ContainsKey($key)) { return $TourImageByName[$key] }
    return $FallbackImage
}
function Get-ProfileDescription {
    param([string]$Label,[string]$HotelName)
    $key = $Label.ToLowerInvariant()
    if ($key -match 'luxury') { return "Premium service, refined surroundings and a polished resort experience." }
    if ($key -match 'couple|honeymoon|romance') { return "Privacy, beautiful scenery and relaxed moments made for two." }
    if ($key -match 'famil') { return "A comfortable resort base with options that work well for different ages." }
    if ($key -match 'wellness|spa') { return "A strong setting for rest, spa time and a slower vacation rhythm." }
    if ($key -match 'golf') { return "A convenient choice for travelers who want to combine resort time and golf." }
    if ($key -match 'food|dining') { return "A good fit for travelers who value dining as part of the resort experience." }
    if ($key -match 'beach') { return "Easy access to the coast for swimming, relaxing and Pacific sunsets." }
    if ($key -match 'design') { return "Distinctive architecture and thoughtful details create a memorable stay." }
    return "A travel style that pairs naturally with the experience offered at $HotelName."
}
function Get-ScoreDescription {
    param([string]$Key,[int]$Score)
    $label = ($Key -replace '_',' ')
    switch -Regex ($Key) {
        'luxury' { return 'Premium service, facilities and overall resort positioning.' }
        'famil' { return 'How comfortably the property works for family travel.' }
        'couple' { return 'Privacy, atmosphere and appeal for couples.' }
        'wellness' { return 'Strength of the relaxation and wellness experience.' }
        'adventure' { return 'Convenience for reaching private tours and outdoor experiences.' }
        'walk' { return 'Ease of moving around without dedicated transportation.' }
        'night' { return 'Availability of social or evening entertainment.' }
        default { return "Local experience score for $label." }
    }
}
function Get-HotelScoreValue {
    param($Value)
    if ($null -eq $Value) { return 0.0 }
    $sp = $Value.PSObject.Properties["score"]
    if ($sp -and $null -ne $sp.Value) { return [double]$sp.Value }
    $n = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $n }
    return 0.0
}
function Get-HotelScoreReason {
    param($Value, [string]$Fallback = "")
    if ($null -ne $Value) {
        $rp = $Value.PSObject.Properties["reason"]
        if ($rp -and -not [string]::IsNullOrWhiteSpace([string]$rp.Value)) { return [string]$rp.Value }
    }
    return $Fallback
}
function Get-TemplateFile {
    param(
        [Parameter(Mandatory = $true)]
        $Entity
    )
    if ($null -eq $Entity) { return "templates/hotel.html" }
    if ($Entity.PSObject.Properties.Name -contains "template") {
        switch ($Entity.template.ToLower()) {
            "experience" { return "templates/experience-guide.html" }
            default      { return "templates/hotel.html" }
        }
    }
    return "templates/hotel.html"
}
function Get-WhyStayHere {
    param($Hotel)
    if ($Hotel.why_stay_here) {
        $summary = [string](Get-PropertyValue $Hotel.why_stay_here "summary" "")
        if (-not [string]::IsNullOrWhiteSpace($summary)) { return $summary }
    }
    $name = [string](Get-PropertyValue $Hotel "name" "This property")
    return "$name is an excellent base for exploring Guanacaste thanks to its location, access to nature, premium accommodations and proximity to Costa Rica's top experiences."
}
function Get-ExperienceHighlights {
    param($Hotel)
    if ($Hotel.experience_highlights) {
        $items = @($Hotel.experience_highlights)
        if ($items.Count -gt 0) { return $items }
    }
    return @(
        [PSCustomObject]@{title="Great Location";description="Easy access to Guanacaste's best attractions."},
        [PSCustomObject]@{title="Nature";description="Surrounded by tropical landscapes."},
        [PSCustomObject]@{title="Comfort";description="Ideal place to relax between adventures."},
        [PSCustomObject]@{title="Private Experiences";description="Perfect starting point for customized tours."}
    )
}
function Get-LocalTips {
    param($Hotel)
    if ($Hotel.local_tips) {
        $items = @($Hotel.local_tips)
        if ($items.Count -gt 0) { return $items }
    }
    return @(
        "Book popular tours early.",
        "Carry sunscreen and water.",
        "Private transportation saves time.",
        "Ask our team for hidden local spots."
    )
}
function Get-SuggestedStay {
    param($Hotel)
    if ($Hotel.suggested_stay) {
        $items = @($Hotel.suggested_stay)
        if ($items.Count -gt 0) { return $items }
    }
    return @(
        [PSCustomObject]@{day=1;title="Arrival";description="Airport transfer and hotel check-in."},
        [PSCustomObject]@{day=2;title="Adventure";description="Recommended signature experience."},
        [PSCustomObject]@{day=3;title="Relax";description="Beach or resort day."},
        [PSCustomObject]@{day=4;title="Departure";description="Transfer to the airport."}
    )
}

$header = [System.IO.File]::ReadAllText($headerPath,[System.Text.Encoding]::UTF8)
$footer = [System.IO.File]::ReadAllText($footerPath,[System.Text.Encoding]::UTF8)
$blogs = if (Test-Path $blogPath) { @(Read-JsonFile $blogPath) } else { @() }
$recommendations = if (Test-Path $recommendationsPath) { Read-JsonFile $recommendationsPath } else { $null }

# V3 pilot: static, hand-curated top-3 override for a small named set of
# hotels only (see knowledge/recommendations/v3-pilot.json). Any problem
# loading or reading it (missing file, malformed JSON, wrong shape) must
# never block hotel generation -- it simply leaves $v3PilotHotels empty,
# which makes every hotel fall through to the unchanged legacy path below.
$v3PilotPath = Join-Path $root "knowledge\recommendations\v3-pilot.json"
$v3PilotHotels = @{}
try {
    if (Test-Path $v3PilotPath) {
        $v3PilotData = Read-JsonFile $v3PilotPath
        if ($v3PilotData -and $v3PilotData.hotels) {
            foreach ($prop in $v3PilotData.hotels.PSObject.Properties) {
                $tourIds = @($prop.Value)
                if ($tourIds.Count -gt 0) { $v3PilotHotels[$prop.Name] = $tourIds }
            }
        }
    }
} catch {
    $v3PilotHotels = @{}
}

$airportsById = @{}
if (Test-Path $airportsPath) {
    $airportsData = [System.IO.File]::ReadAllText($airportsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $airportItems = if ($airportsData.PSObject.Properties["airports"]) { @($airportsData.airports) } else { @($airportsData) }
    foreach ($airport in $airportItems) {
        $airportId = if ($airport.id) { [string]$airport.id } elseif ($airport.code) { [string]$airport.code } elseif ($airport.iata) { [string]$airport.iata } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($airportId)) { $airportsById[$airportId.Trim().ToLowerInvariant()] = $airport }
    }
} else { Write-Warning "Airport repository not found: $airportsPath" }
$destinationById = @{}
foreach ($file in @(Get-ChildItem $destinationDir -Filter "*.json" -File)) { $d = Read-JsonFile $file.FullName; $destinationById[[string]$d.id] = $d }
$tourById = @{}
$tourImageByName = @{}
foreach ($file in @(Get-ChildItem $tourDir -Filter "*.json" -File)) {
    $t = Read-JsonFile $file.FullName
    $tourById[[string]$t.id] = $t
    if ($t.name -and $t.hero_image) { $tourImageByName[([string]$t.name).ToLowerInvariant()] = [string]$t.hero_image }
}

$hotels = @()
foreach ($file in @(Get-ChildItem $hotelDir -Filter "*.json" -File | Sort-Object Name)) { $hotels += Read-JsonFile $file.FullName }
$generated = 0
$warnings = @()

# Hotel-specific "private tours" landing pages (e.g. Four Seasons, Andaz)
# link back from their hotel guide instead of the generic /tours.html --
# built from knowledge/landing-pages/*.json's own hotel_id tag so new
# landings automatically wire up without touching this generator again.
$landingPagesDir = Join-Path $root "knowledge\landing-pages"
$landingByHotelId = @{}
if (Test-Path $landingPagesDir) {
    Get-ChildItem $landingPagesDir -Filter "*.json" -File | ForEach-Object {
        $lp = Read-JsonFile $_.FullName
        $hid = [string](Get-PropertyValue $lp 'hotel_id' '')
        if ($hid) { $landingByHotelId[$hid] = $lp }
    }
}

foreach ($hotel in $hotels) {
    if ([string](Get-PropertyValue $hotel "status" "review") -eq "disabled") { continue }

    $templatePath = Join-Path $root (Get-TemplateFile $hotel)
    $template = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)

    $id = [string]$hotel.id
    $slug = [string]$hotel.slug
    $short = Get-ShortHotelName $hotel
    $airportId = [string]$hotel.airport_id
    $airport = $null
    if (-not [string]::IsNullOrWhiteSpace($airportId)) {
        $airportKey = $airportId.Trim().ToLowerInvariant()
        if ($airportsById.ContainsKey($airportKey)) { $airport = $airportsById[$airportKey] }
    }
    if (-not $airport) { $warnings += "$slug`: airport '$airportId' not found" }
    $destination = $destinationById[[string]$hotel.destination_id]
    if ($null -eq $destination) { $warnings += "$slug`: destination '$($hotel.destination_id)' not found" }

    $airportName = switch (([string]$hotel.airport_id).ToLowerInvariant()) {
        "lir"   { "Guanacaste (LIR)" }
        "sjo"   { "San Jose (SJO)"   }
        default { if ($airport) { "$($airport.name) ($($airport.iata))" } else { ([string]$hotel.airport_id).ToUpperInvariant() } }
    }
    $destinationName = if ($destination) { [string]$destination.name } else { [string]$hotel.destination_id }
    $transferObject = Get-PropertyValue $hotel "transfer_minutes" $null
    $transferShort = if ($transferObject) { "$($transferObject.min)-$($transferObject.max) minutes" } else { "Varies" }
    $transferLabel = if ($transferObject -and $transferObject.label) { [string]$transferObject.label } else { "Private transfer time from $airportName varies -- ask our team for an exact estimate." }

    $airportNameByCode = @{ lir = "Guanacaste Airport (LIR)"; sjo = "San Jose Airport (SJO)" }
    $airportShortNameByCode = @{ lir = "Guanacaste (LIR)"; sjo = "San Jose (SJO)" }
    $transferByAirport = Get-PropertyValue $hotel "transfer_by_airport" $null
    $bothAirportsHtml = ""
    if ($transferByAirport) {
        # Pick the airport with the shortest real drive time as the "nearest airport" shown
        # in the hero/quick-facts -- using the actual computed minutes (not the static
        # airport_id field) so it can never contradict the dual-airport panel below.
        $nearestCode = $null
        $nearestMin = [double]::MaxValue
        $rows = ""
        foreach ($code in @('lir','sjo')) {
            $entry = Get-PropertyValue $transferByAirport $code $null
            if ($entry) {
                $label = $airportNameByCode[$code]
                $rows += '<div class="hp-transport-row"><strong>' + $label + '</strong><p>' + $entry.min + '-' + $entry.max + ' minutes (' + $entry.km + ' km) by private transfer.</p></div>'
                if ([double]$entry.min -lt $nearestMin) { $nearestMin = [double]$entry.min; $nearestCode = $code }
            }
        }
        if ($rows) { $bothAirportsHtml = $rows }
        if ($nearestCode) {
            $nearestEntry = Get-PropertyValue $transferByAirport $nearestCode $null
            $airportName = $airportShortNameByCode[$nearestCode]
            $transferShort = "$($nearestEntry.min)-$($nearestEntry.max) minutes"
            $transferLabel = "Approximately $($nearestEntry.min)-$($nearestEntry.max) minutes ($($nearestEntry.km) km) by private transfer from $($nearestEntry.airport_name), based on real driving distance."
            if ($airportsById.ContainsKey($nearestCode)) { $airport = $airportsById[$nearestCode] }
        }
    }
    $coordinates = Get-PropertyValue $hotel "coordinates" $null
    $formattedAddress = [string](Get-PropertyValue $hotel "formatted_address" "")
    $addressHtml = if ($formattedAddress) { '<p class="hp-address">' + (ConvertTo-HtmlSafe $formattedAddress) + '</p>' } else { '' }

    $scoreValues = @()
    $scores = Get-PropertyValue $hotel "hotel_scores" $null
    if ($scores) { foreach ($p in $scores.PSObject.Properties) { $scoreValues += Get-HotelScoreValue $p.Value } }
    $overallScore = if ($scoreValues.Count -gt 0) { [Math]::Round((($scoreValues | Measure-Object -Average).Average),1) } else { 4.5 }
    $overallStars = Get-StarHtml $overallScore

    $facts = @(
        @{label="Location";value=$destinationName;icon="location"},
        @{label="Nearest airport";value=$airportName;icon="airport"},
        @{label="Private transfer";value=$transferShort;icon="transfer"},
        @{label="Resort style";value=[string]$hotel.category;icon="luxury"}
    )
    $factsHtml = ""
    foreach ($fact in $facts) {
        $factsHtml += '<div class="hp-fact"><span class="hp-fact-icon">' + (Get-IconHtml $fact.icon) + '</span><div><small>' + (ConvertTo-HtmlSafe $fact.label) + '</small><strong>' + (ConvertTo-HtmlSafe $fact.value) + '</strong></div></div>'
    }

    $profileReasonByName = @{}
    foreach ($pr in @(Get-PropertyValue $hotel 'traveler_profile_reasons' @())) {
        $prName = [string](Get-PropertyValue $pr 'profile' '')
        $prReason = [string](Get-PropertyValue $pr 'reason' '')
        if ($prName -and $prReason) { $profileReasonByName[$prName.ToLowerInvariant()] = $prReason }
    }

    $loveCards = ""
    $loveProfiles = @(Get-ArrayValue $hotel.best_for | Select-Object -First 4)
    foreach ($loveProfile in $loveProfiles) {
        $profileText = [string]$loveProfile
        $profileDesc = if ($profileReasonByName.ContainsKey($profileText.ToLowerInvariant())) { $profileReasonByName[$profileText.ToLowerInvariant()] } else { Get-ProfileDescription $profileText $short }
        $loveCards += '<article class="hp-love-card"><div class="hp-love-icon">' + (Get-IconHtml $profileText) + '</div><h3>' + (ConvertTo-HtmlSafe $profileText) + '</h3><p>' + (ConvertTo-HtmlSafe $profileDesc) + '</p></article>'
    }

    $googleReviews = Get-PropertyValue $hotel "google_reviews" $null

    $scoresHtml = ""
    if ($scores) {
        foreach ($p in $scores.PSObject.Properties) {
            $score = Get-HotelScoreValue $p.Value
            if ($score -lt 0) { $score = 0 }
            if ($score -gt 5) { $score = 5 }
            $label = ($p.Name -replace '_',' ')
            $fallbackReason = Get-ScoreDescription $p.Name ([int]$score)
            $scoreReason = Get-HotelScoreReason $p.Value $fallbackReason
            $scoresHtml += '<div class="hp-rating-row" title="' + (ConvertTo-HtmlSafe $scoreReason) + '"><strong>' + (ConvertTo-HtmlSafe $label) + '</strong>' + (Get-StarHtml $score) + '<span class="hp-rating-number">' + $score.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture) + '</span></div>'
        }
    }

    # Every category defaulting to the same untouched value (3) means no one
    # has actually assessed this hotel yet -- showing identical "3.0" stars
    # across 7 unrelated categories (luxury, nightlife, wellness...) reads as
    # fabricated to visitors and undermines trust in the rest of the page.
    # Show real stars when at least one category has been differentiated;
    # otherwise show an honest "not yet rated" state instead of fake precision.
    $hasRealScores = ($scoreValues.Count -gt 0) -and (@($scoreValues | Where-Object { $_ -ne 3 }).Count -gt 0)

    if ($hasRealScores) {
        $ratingPanelBlock = '<div class="hp-rating-panel"><div class="hp-panel-title">Experience rating</div>' + $scoresHtml + '<div class="hp-overall"><div><strong>' + $overallScore.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture) + ' / 5</strong><p>Overall local experience profile</p></div>' + $overallStars + '</div></div>'
    } else {
        $ratingPanelBlock = ''
    }

    # Both the hero badge and the insight-panel badge used to show a fabricated
    # "Local experience profile" / "Wild Papagayo Recommended" score derived from
    # the same untouched default hotel_scores as $hasRealScores above -- replaced
    # with the real Google rating so both badges show genuine, verifiable data.
    if ($googleReviews -and $googleReviews.rating) {
        $googleStarsSmall = Get-StarHtml ([double]$googleReviews.rating)
        $googleRatingText = ([double]$googleReviews.rating).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
        $googleBadge = Get-GoogleBadgeHtml
        $insightRatingBlock = $googleBadge + $googleStarsSmall + '<strong>' + $googleRatingText + ' / 5 on Google</strong><p style="margin-top:6px;font-size:.75rem;color:var(--hp-muted)">' + [string]$googleReviews.review_count + ' verified reviews</p>'
        # Hero facts strip: real Google rating + review count + transfer time.
        # No photo needed -- these are the three most decision-relevant, fully
        # verifiable facts about the property, replacing an unlicensed image.
        $heroFactsStrip = '<div class="hp-hero-facts">' +
            '<div class="hp-hero-fact"><strong>' + $googleRatingText + '</strong><small>Google Rating</small></div>' +
            '<div class="hp-hero-fact"><strong>' + [string]$googleReviews.review_count + '</strong><small>Reviews</small></div>' +
            '<div class="hp-hero-fact"><strong>' + (ConvertTo-HtmlSafe $transferShort) + '</strong><small>From ' + (ConvertTo-HtmlSafe $airport.iata) + '</small></div>' +
            '</div>'
    } else {
        $insightRatingBlock = '<strong>Wild Papagayo Recommended</strong>'
        $heroFactsStrip = '<div class="hp-hero-facts">' +
            '<div class="hp-hero-fact"><strong>' + (ConvertTo-HtmlSafe $hotel.category) + '</strong><small>Resort Style</small></div>' +
            '<div class="hp-hero-fact"><strong>' + (ConvertTo-HtmlSafe $transferShort) + '</strong><small>From ' + (ConvertTo-HtmlSafe $airport.iata) + '</small></div>' +
            '</div>'
    }

    $recommended = @()

    # V3 pilot: only engages for hotel IDs explicitly present in
    # v3-pilot.json. Any referenced tour ID not found in $tourById is
    # skipped rather than breaking the page; if that leaves nothing
    # resolvable, $recommended stays empty and legacy below takes over.
    if ($v3PilotHotels.ContainsKey($id)) {
        foreach ($tourId in $v3PilotHotels[$id]) {
            if ($tourById.ContainsKey([string]$tourId)) {
                $t = $tourById[[string]$tourId]
                $recommended += [pscustomobject]@{id=$t.id; name=$t.name}
            }
        }
    }

    if ($recommended.Count -eq 0 -and $recommendations -and $recommendations.hotel_tours) {
        $prop = $recommendations.hotel_tours.PSObject.Properties[$id]
        if ($prop) { $recommended = @($prop.Value) }
    }
    if ($recommended.Count -eq 0) {
        foreach ($tourId in (Get-ArrayValue $hotel.featured_tours)) {
            if ($tourById.ContainsKey([string]$tourId)) {
                $t = $tourById[[string]$tourId]
                $recommended += [pscustomobject]@{id=$t.id;name=$t.name;score=0;reasons=@("Featured for this hotel");category=$t.category;url=$t.page_url;image=$t.hero_image;duration=$t.duration_label}
            }
        }
    }

    $tourCards = ""
    $tourIndex = 0
    $badgeLabels = @("Most popular","Local favorite","Adventure pick")
    foreach ($rec in @($recommended | Select-Object -First 3)) {
        $tour = $tourById[[string]$rec.id]
        $name = if ($rec.name) { [string]$rec.name } elseif ($tour) { [string]$tour.name } else { [string]$rec.id }
        $category = if ($rec.category) { [string]$rec.category } elseif ($tour) { [string]$tour.category } else { "Experience" }
        $url = if ($rec.url) { [string]$rec.url } elseif ($tour) { [string]$tour.page_url } else { "tours.html" }
        $image = if ($rec.image) { [string]$rec.image } elseif ($tour) { [string]$tour.hero_image } else { [string]$hotel.hero_image }
        $desc = if ($tour) { [string](Get-PropertyValue $tour "short_description" (Get-PropertyValue $tour "description" "Private Costa Rica experience.")) } else { "Private Costa Rica experience." }
        $duration = if ($rec.duration) { [string]$rec.duration } elseif ($tour) { [string](Get-PropertyValue $tour "duration_label" "Private experience") } else { "Private experience" }
        $badge = $badgeLabels[[Math]::Min($tourIndex,$badgeLabels.Count-1)]
        # $url (page_url / rec.url) is already root-relative from a one-level-deep page (e.g. "../tours/x.html") -- do not prepend another "../"
        $tourCards += '<a class="hp-experience" href="' + (ConvertTo-HtmlSafe $url) + '"><span class="hp-badge">' + $badge + '</span><img src="../' + (ConvertTo-HtmlSafe $image) + '" alt="' + (ConvertTo-HtmlSafe $name) + '" loading="lazy"><div class="hp-experience-body"><h3>' + (ConvertTo-HtmlSafe $name) + '</h3><div class="hp-experience-meta"><span>' + (ConvertTo-HtmlSafe $duration) + '</span><span>' + (ConvertTo-HtmlSafe $category) + '</span></div><p>' + (ConvertTo-HtmlSafe $desc) + '</p><div class="hp-experience-footer">' + (Get-StarHtml 5) + '<span class="hp-experience-link">View experience</span></div></div></a>'
        $tourIndex++
    }
    if ([string]::IsNullOrWhiteSpace($tourCards)) { $tourCards = '<p>No tour recommendations are available yet.</p>' }

    # Opt-out switch, per hotel -- lets a hotel with its own richer excursion
    # guide (below) suppress this older 3-card teaser instead of showing both
    # as competing decision paths. Defaults to shown (false) for every other
    # hotel; the shared component itself is untouched.
    $suppressCuratedExperiences = [bool](Get-PropertyValue $hotel 'suppress_curated_experiences' $false)
    $curatedExperiencesSectionHtml = if ($suppressCuratedExperiences) {
        ""
    } else {
        '<section class="hp-section hp-section-soft"><div class="hp-wrap"><div class="hp-heading"><div class="hp-eyebrow">Signature experiences</div><h2>Curated experiences from this resort</h2></div><div class="hp-experience-grid">' + $tourCards + '</div></div></section>'
    }

    # ---- Excursion Guide ("Best Tours & Excursions from <Hotel>") ----
    # Opt-in via excursion_guide -- only renders when a hotel record has this
    # curated list, so it changes nothing for hotels that don't have it yet.
    $excursionGuideSectionHtml = ""
    $excursionEntries = @(Get-PropertyValue $hotel 'excursion_guide' @())
    if ($excursionEntries.Count -gt 0) {
        $egItems = ($excursionEntries | ForEach-Object {
            $entry = $_
            $t = $tourById[[string]$entry.tour_id]
            if (-not $t) { return }
            $egImg = [string](Get-PropertyValue $t 'hero_image' '')
            $egImgAlt = [string](Get-PropertyValue $t 'hero_image_alt' $t.name)
            $egImgHtml = if ($egImg) { '<div class="eg-item-media"><img src="../' + (ConvertTo-HtmlSafe $egImg) + '" alt="' + (ConvertTo-HtmlSafe $egImgAlt) + '" loading="lazy" decoding="async"></div>' } else { '' }
            '<div class="eg-item">' + $egImgHtml + '<div class="eg-item-body"><span class="eg-tag">Best for ' + (ConvertTo-HtmlSafe $entry.best_for) + '</span><h3>' + (ConvertTo-HtmlSafe $t.name) + '</h3><p>' + (ConvertTo-HtmlSafe $entry.why) + '</p><div class="eg-item-footer"><span class="eg-meta">' + (ConvertTo-HtmlSafe $t.duration_label) + '</span><a class="eg-link" href="' + (ConvertTo-HtmlSafe $t.page_url) + '">View this tour &rarr;</a></div></div></div>'
        }) -join ''
        if ($egItems) {
            $excursionIntro = [string](Get-PropertyValue $hotel 'excursion_intro' '')
            $introHtml = if ($excursionIntro) { '<p class="eg-intro">' + (ConvertTo-HtmlSafe $excursionIntro) + '</p>' } else { '' }
            $compareHtml = '<div class="eg-compare"><p>' + (ConvertTo-HtmlSafe $short) + ' offers its own excursion desk, and many guests are happy booking directly through the resort. Wild Papagayo offers a different, complementary option: a private vehicle and private guide for your group only, with pickup timed to your schedule rather than a shared departure window. That makes it easier to combine experiences, travel at your own pace, and adjust plans around young kids or a more relaxed morning. Both approaches are valid, the right choice depends on whether you would rather join a scheduled group activity or keep your day fully private.</p></div>'
            $excursionGuideSectionHtml = '<section class="hp-section"><div class="hp-wrap"><div class="hp-heading"><div class="hp-eyebrow">Plan your excursions</div><h2>Best Tours &amp; Excursions From ' + (ConvertTo-HtmlSafe $short) + '</h2></div>' + $introHtml + '<div class="eg-list">' + $egItems + '</div></div></section>' +
                '<section class="hp-section hp-section-soft"><div class="hp-wrap"><div class="hp-heading"><div class="hp-eyebrow">Two ways to explore</div><h2>Private Tours vs. Resort-Organized Excursions</h2></div>' + $compareHtml + '</div></section>'
        }
    }

    # ---- Private Tours intro + pickup blurb (generic, data-driven per hotel) ----
    $recNames = @($recommended | Select-Object -First 3 | ForEach-Object { [string]$_.name } | Where-Object { $_ })
    $recNamesJoined = if ($recNames.Count -gt 0) { ($recNames -join ', ') } else { '' }
    $privateToursIntro = '<p>Staying at ' + (ConvertTo-HtmlSafe $short) + ' makes it easy to explore ' + (ConvertTo-HtmlSafe $destinationName) + ' and Guanacaste beyond the resort. Wild Papagayo offers private tours with hotel pickup from ' + (ConvertTo-HtmlSafe $short) + ' to waterfalls, wildlife areas, volcanoes, hot springs and adventure destinations throughout the region.</p>'
    if ($recNamesJoined) {
        $privateToursIntro += '<p>Popular options include ' + (ConvertTo-HtmlSafe $recNamesJoined) + ' and other private day trips tailored to your group.</p>'
    }
    $hotelLanding = $landingByHotelId[[string]$hotel.id]
    $privateToursLinkUrl = if ($hotelLanding) { '../private-tours/' + [string]$hotelLanding.slug + '.html' } else { '../tours.html' }
    $privateToursLinkText = if ($hotelLanding) { 'Explore Private Tours From ' + $short } else { 'Explore Private Tours' }
    $privateToursIntro += '<a class="hp-btn hp-btn-outline-navy" href="' + (ConvertTo-HtmlSafe $privateToursLinkUrl) + '">' + (ConvertTo-HtmlSafe $privateToursLinkText) + '</a>'

    # Opt-out switch, per hotel -- for a hotel with its own richer excursion
    # guide (below), this older intro+button teaser becomes a redundant,
    # near-duplicate section covering the same intent. Defaults to shown
    # (false) for every other hotel; the shared component itself is untouched.
    $suppressPrivateToursIntro = [bool](Get-PropertyValue $hotel 'suppress_private_tours_intro' $false)
    $privateToursSectionHtml = if ($suppressPrivateToursIntro) {
        ""
    } else {
        '<section class="hp-section"><div class="hp-wrap"><div class="hp-heading"><div class="hp-eyebrow">Private Tours</div><h2>Private Tours From ' + (ConvertTo-HtmlSafe $short) + '</h2></div>' + $privateToursIntro + '</div></section>'
    }

    $pickupBlurb = '<div class="hp-transport-row"><strong>Private Tour Pickup</strong><p>Wild Papagayo can arrange private pickup directly from ' + (ConvertTo-HtmlSafe $short) + ' for tours and excursions. Your departure time is coordinated around your selected experience, group size and itinerary, so you do not need to travel to a separate meeting point.</p></div>'
    $transferLandingUrl = [string](Get-PropertyValue $hotel 'transfer_landing_url' '')
    $airportBlurb = if ([string]$hotel.airport_id -eq 'lir') {
        $airportLinks = '<a href="../blog/liberia-airport-transfer-guide.html">Read our Liberia Airport Transportation Guide &rarr;</a>'
        if ($transferLandingUrl) {
            $airportLinks += ' <a href="../' + (ConvertTo-HtmlSafe $transferLandingUrl) + '">Book Your Private Transfer to ' + (ConvertTo-HtmlSafe $short) + ' &rarr;</a>'
        }
        '<div class="hp-transport-row"><strong>Liberia Airport Transportation</strong><p>' + (ConvertTo-HtmlSafe $short) + ' is served by Guanacaste Airport (LIR). ' + $airportLinks + '</p></div>'
    } else { '' }

    $itineraryTours = @($recommended | Select-Object -First 2)
    $day2 = if ($itineraryTours.Count -gt 0) { [string]$itineraryTours[0].name } else { "Private adventure" }
    $day3 = if ($itineraryTours.Count -gt 1) { [string]$itineraryTours[1].name } else { "Relax and explore" }
    $itineraryHtml = ''
    $itineraryItems = @(
        @{day='Day 1';title='Arrival';text='Private airport transfer and a relaxed first evening.';icon='arrival'},
        @{day='Day 2';title=$day2;text='A curated day experience with hotel pickup.';icon='adventure'},
        @{day='Day 3';title=$day3;text='Balance exploration with time to enjoy the resort.';icon='nature'},
        @{day='Day 4';title='Departure';text='A comfortable private transfer back to the airport.';icon='departure'}
    )
    foreach ($item in $itineraryItems) {
        $dayImg = Get-DayImage $item.title $tourImageByName $hotel.hero_image
        $itineraryHtml += '<article class="hp-day-card"><div class="hp-day-card-media" style="background-image:url(&quot;../' + (ConvertTo-HtmlSafe $dayImg) + '&quot;)"><span class="hp-day-badge">' + $item.day + '</span></div><div class="hp-day-card-body"><h3>' + (ConvertTo-HtmlSafe $item.title) + '</h3><p>' + (ConvertTo-HtmlSafe $item.text) + '</p></div></article>'
    }

    # "What Guests Are Saying" -- replaces the old "Perfect N-day stay" itinerary block,
    # which just re-showed the same 3 tours already listed in Curated Experiences above.
    # Real Google rating + real guest review quotes instead (hotel-reviews-finder.ps1).
    $reviewsSection = ""
    $googleReviews = Get-PropertyValue $hotel "google_reviews" $null
    if ($googleReviews -and @($googleReviews.reviews).Count -gt 0) {
        $reviewCards = (@($googleReviews.reviews) | ForEach-Object {
            $stars = Get-StarHtml ([double]$_.rating)
            $relativeTimeHtml = if ($_.relative_time) { '<small>' + (ConvertTo-HtmlSafe $_.relative_time) + '</small>' } else { '' }
            '<div class="hp-review-card">' + $stars + '<p>&ldquo;' + (ConvertTo-HtmlSafe $_.text) + '&rdquo;</p><strong>' + (ConvertTo-HtmlSafe $_.author) + '</strong>' + $relativeTimeHtml + '</div>'
        }) -join ''
        $overallGoogleStars = Get-StarHtml ([double]$googleReviews.rating)
        $reviewsSection = '<section class="hp-section hp-section-soft"><div class="hp-wrap"><div class="hp-heading"><div class="hp-eyebrow">Real guest sentiment</div><h2>What Guests Are Saying</h2><p>' + (Get-GoogleBadgeHtml) + $overallGoogleStars + ' <strong>' + ([double]$googleReviews.rating).ToString([System.Globalization.CultureInfo]::InvariantCulture) + '/5</strong> on Google &middot; ' + [string]$googleReviews.review_count + ' reviews</p></div><div class="hp-review-grid">' + $reviewCards + '</div></div></section>'
    }

    $nearbyCards = ""
    foreach ($destId in (Get-ArrayValue $hotel.nearby_destinations | Select-Object -First 3)) {
        if ($destinationById.ContainsKey([string]$destId)) {
            $d = $destinationById[[string]$destId]
            $destImage = [string](Get-PropertyValue $d "hero_image" $hotel.hero_image)
            $destSlug = [string](Get-PropertyValue $d "slug" $d.id)
            if ([string]::IsNullOrWhiteSpace($destSlug)) { $destSlug = [string]$d.id }
            $nearbyCards += '<a class="hp-nearby" href="../destinations/' + (ConvertTo-HtmlSafe $destSlug) + '.html" style="background-image:url(&quot;../' + (ConvertTo-HtmlSafe $destImage) + '&quot;)"><span><small>Explore nearby</small>' + (ConvertTo-HtmlSafe $d.name) + '</span></a>'
        }
    }
    if ([string]::IsNullOrWhiteSpace($nearbyCards) -and $destination) {
        $destImage = [string](Get-PropertyValue $destination "hero_image" $hotel.hero_image)
        $nearbyCards = '<a class="hp-nearby" href="../destinations/' + (ConvertTo-HtmlSafe $destination.id) + '.html" style="background-image:url(&quot;../' + (ConvertTo-HtmlSafe $destImage) + '&quot;)"><span><small>Explore nearby</small>' + (ConvertTo-HtmlSafe $destination.name) + '</span></a>'
    }

    $articleCards = ""
    # Auto-discover relevant articles instead of relying only on a manually
    # curated list -- match any article that names this hotel directly, or
    # that covers this hotel's destination (e.g. a "Is Papagayo safe for
    # families?" Q&A should surface on every Papagayo hotel automatically).
    $curatedSlugs = @(Get-ArrayValue $hotel.related_articles)
    $hotelId = [string]$hotel.id
    $hotelDestId = [string]$hotel.destination_id
    $directMatches = @($blogs | Where-Object { @(Get-ArrayValue $_.hotel_ids) -contains $hotelId })
    # Exclude articles tied to any OTHER specific hotel (e.g. "Best Tours From
    # Riu Guanacaste" naming a sibling property) from the generic same-destination
    # pool -- those should only ever surface as a directMatch on their own hotel's
    # page, never as a same-zone "related article" on a different hotel's page.
    $destMatches = @($blogs | Where-Object {
        (@(Get-ArrayValue $_.hotel_ids)).Count -eq 0 -and
        ((@(Get-ArrayValue $_.destination_ids) -contains $hotelDestId) -or (@(Get-ArrayValue $_.destinations) -contains $hotelDestId))
    })
    # Most articles aren't tied to one specific hotel, so every hotel in the
    # same destination shares the same destMatches pool -- shuffle that pool
    # with a per-hotel seed (same trick as featured tours) so hotels in the
    # same zone don't all show an identical trio of "related" articles.
    if ($destMatches.Count -gt 1) {
        $seedBytes = [System.Text.Encoding]::UTF8.GetBytes("articles-$hotelId")
        $seed = [System.BitConverter]::ToInt32(([System.Security.Cryptography.MD5]::Create().ComputeHash($seedBytes)), 0)
        $rng = New-Object System.Random($seed)
        $destMatches = @($destMatches | Sort-Object { $rng.Next() })
    }
    $curatedMatches = @($blogs | Where-Object { $curatedSlugs -contains $_.slug })
    $seenSlugs = New-Object System.Collections.Generic.HashSet[string]
    $relevantArticles = New-Object System.Collections.Generic.List[object]
    foreach ($article in (@($directMatches) + @($destMatches) + @($curatedMatches))) {
        if ($seenSlugs.Add([string]$article.slug)) { $relevantArticles.Add($article) }
    }
    foreach ($article in @($relevantArticles | Select-Object -First 3)) {
        $articleImage = [string](Get-PropertyValue $article "image_top" $hotel.hero_image)
        $articleCards += '<a class="hp-article" href="../blog/' + (ConvertTo-HtmlSafe $article.slug) + '.html"><img src="../' + (ConvertTo-HtmlSafe $articleImage) + '" alt="' + (ConvertTo-HtmlSafe $article.image_top_alt) + '" loading="lazy"><div><small>' + (ConvertTo-HtmlSafe $article.category) + '</small><h3>' + (ConvertTo-HtmlSafe $article.title) + '</h3><p>' + (ConvertTo-HtmlSafe $article.excerpt) + '</p></div></a>'
    }
    if ([string]::IsNullOrWhiteSpace($articleCards)) {
        $articleCards = '<a class="hp-article" href="../Blogs.html"><div><small>Insider guide</small><h3>Explore Costa Rica travel advice</h3><p>Browse practical local guides for transportation, destinations and private experiences.</p></div></a>'
    }

    $faqHtml = ""
    $faqEntities = @()
    foreach ($faq in (Get-ArrayValue $hotel.faq)) {
        $faqHtml += '<details class="hp-faq"><summary>' + (ConvertTo-HtmlSafe $faq.q) + '</summary><p>' + (ConvertTo-HtmlSafe $faq.a) + '</p></details>'
        $faqEntities += @{"@type"="Question";name=[string]$faq.q;acceptedAnswer=@{"@type"="Answer";text=[string]$faq.a}}
    }

    $WhyStayHere  = Get-WhyStayHere  $hotel
    $Highlights   = Get-ExperienceHighlights $hotel
    $LocalTips    = Get-LocalTips    $hotel
    $SuggestedStay = Get-SuggestedStay $hotel

    $highlightsHtml = ""
    foreach ($h in @($Highlights | Select-Object -First 4)) {
        $hTitle = [string](Get-PropertyValue $h "title" "")
        $hDesc  = [string](Get-PropertyValue $h "description" "")
        $highlightsHtml += '<article class="hp-love-card"><div class="hp-love-icon">' + (Get-IconHtml $hTitle) + '</div><h3>' + (ConvertTo-HtmlSafe $hTitle) + '</h3><p>' + (ConvertTo-HtmlSafe $hDesc) + '</p></article>'
    }

    $localTipsHtml = '<ul class="hp-tips-list">'
    foreach ($tip in @($LocalTips)) {
        $localTipsHtml += '<li>' + (ConvertTo-HtmlSafe ([string]$tip)) + '</li>'
    }
    $localTipsHtml += '</ul>'

    $suggestedStayHtml = ""
    $dayIndex = 1
    foreach ($dayItem in @($SuggestedStay)) {
        $dayNum   = [string](Get-PropertyValue $dayItem "day" $dayIndex)
        $dayTitle = [string](Get-PropertyValue $dayItem "title" "Day $dayNum")
        $dayDesc  = [string](Get-PropertyValue $dayItem "description" "")
        $dayImg = Get-DayImage $dayTitle $tourImageByName $hotel.hero_image
        $suggestedStayHtml += '<article class="hp-day-card"><div class="hp-day-card-media" style="background-image:url(&quot;../' + (ConvertTo-HtmlSafe $dayImg) + '&quot;)"><span class="hp-day-badge">Day ' + $dayNum + '</span></div><div class="hp-day-card-body"><h3>' + (ConvertTo-HtmlSafe $dayTitle) + '</h3><p>' + (ConvertTo-HtmlSafe $dayDesc) + '</p></div></article>'
        $dayIndex++
    }

    # Interactive map: prefer the real geocoded coordinates (hotel-transfer-time-finder.ps1)
    # over a text-name search -- exact coordinates avoid Google Maps occasionally resolving
    # a boutique property's name to the wrong pin.
    $mapLink = ""
    if ($coordinates -and $coordinates.lat -and $coordinates.lng) {
        $mapQ = "$($coordinates.lat),$($coordinates.lng)"
        $mapLink = "https://www.google.com/maps/search/?api=1&query=$mapQ"
    } else {
        $mapQueryText = if ($hotel.location_label) { "$($hotel.name), $($hotel.location_label), Costa Rica" } else { "$($hotel.name), Costa Rica" }
        $mapQ = [Uri]::EscapeDataString($mapQueryText)
        $mapLink = "https://www.google.com/maps/search/?api=1&query=$mapQ"
    }
    $mapEmbed = '<iframe src="https://www.google.com/maps?q=' + $mapQ + '&output=embed" loading="lazy" referrerpolicy="no-referrer-when-downgrade" title="Map of ' + (ConvertTo-HtmlSafe $hotel.name) + '"></iframe>'
    $mapLinkHtml = '<a class="hp-map-link" href="' + $mapLink + '" target="_blank" rel="noopener">Open in Google Maps &rarr;</a>'

    # Best time to visit: reuses the destination's real best_season data (dry/green season),
    # already Claude-scored with real reasons -- no restaurant/wildlife data needed for this part.
    $bestTimeHtml = ""
    if ($destination -and $destination.best_season) {
        $destSlug = [string]$destination.id
        $bestTimeHtml = '<div class="hp-besttime-grid">' +
            '<div class="hp-besttime-card"><div class="hp-besttime-icon">' + (Get-IconHtml 'season') + '</div><h3>' + (ConvertTo-HtmlSafe $destination.name) + '</h3><p>Best visited ' + (ConvertTo-HtmlSafe $destination.best_season) + '.</p><a href="../destinations/' + $destSlug + '.html">See the full ' + (ConvertTo-HtmlSafe $destination.name) + ' travel guide &rarr;</a></div>' +
            '<div class="hp-besttime-card"><div class="hp-besttime-icon">' + (Get-IconHtml 'calendar') + '</div><h3>Costa Rica, month by month</h3><p>Compare rainfall, temperatures and crowds across the whole country.</p><a href="../months.html">Browse weather by month &rarr;</a></div>' +
            '</div>'
    } else {
        $bestTimeHtml = '<div class="hp-besttime-grid">' +
            '<div class="hp-besttime-card"><div class="hp-besttime-icon">' + (Get-IconHtml 'calendar') + '</div><h3>Costa Rica, month by month</h3><p>Compare rainfall, temperatures and crowds across the whole country.</p><a href="../months.html">Browse weather by month &rarr;</a></div>' +
            '</div>'
    }

    # Nearby restaurants: reuses the destination's Google Places list (restaurant-finder.ps1)
    # rather than a separate per-hotel API call -- same real data, best-rated 6 shown (sorted
    # by rating then review count, not insertion order -- a hotel page previously showed
    # whichever 3 happened to be saved first, which weren't necessarily the best options).
    # Full section (including heading) built here so it disappears entirely when there's no data.
    # Opt-out switch, per hotel -- this section reuses the shared destination-wide
    # restaurant list (not filtered by real proximity to each specific hotel), which
    # can read as irrelevant on a hotel where none of those restaurants are actually
    # close. Defaults to shown (false) everywhere else; the shared data/logic below
    # is untouched.
    $suppressRestaurantsSection = [bool](Get-PropertyValue $hotel 'suppress_restaurants_section' $false)
    $restaurantsSection = ""
    if (-not $suppressRestaurantsSection -and $destination -and $destination.restaurants -and @($destination.restaurants).Count -gt 0) {
        $topRestaurants = @($destination.restaurants | Sort-Object -Property @{Expression={[double]$_.rating}; Descending=$true}, @{Expression={[int]$_.review_count}; Descending=$true} | Select-Object -First 6)
        $restaurantCards = ($topRestaurants | ForEach-Object {
            $ratingText = ([double]$_.rating).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
            '<div class="hp-restaurant-card"><h3>' + (ConvertTo-HtmlSafe $_.name) + '</h3><div class="hp-restaurant-rating">&#9733; ' + $ratingText + ' <small>(' + (ConvertTo-HtmlSafe $_.review_count) + ' reviews)</small></div></div>'
        }) -join ''
        $restaurantsSection = '<section class="hp-section"><div class="hp-wrap"><div class="hp-heading"><div class="hp-eyebrow">Planning your trip</div><h2>Where to Eat Nearby</h2><p>Real, currently-rated options near ' + (ConvertTo-HtmlSafe $destination.name) + ', sourced live from Google.</p></div><div class="hp-restaurant-grid">' + $restaurantCards + '</div></div></section>'
    }

    $localInsight = [string](Get-PropertyValue $hotel "local_insight" $hotel.description)
    $heroDescription = [string](Get-PropertyValue $hotel "hero_description" $hotel.description)
    $canon = "$siteUrl/hotels/$slug"
    # Not the hotel's Google-sourced photo (we don't hold rights to redistribute
    # those in social previews or Google's own rich-result image field) -- the
    # generic Wild Papagayo brand photo used sitewide for the same purpose.
    $og = "$siteUrl/images/luxury-costa-rica-tours-hero.webp"
    $hotelSchema = [ordered]@{"@type"="Hotel";"@id"="$canon#hotel";name=[string]$hotel.name;description=[string]$hotel.description;image=$og;url=$canon;address=@{"@type"="PostalAddress";addressLocality=[string]$hotel.location_label;addressRegion=[string]$hotel.province;addressCountry="CR"};sameAs=@([string]$hotel.official_url)}

    # Real geo + aggregateRating + review markup -- sourced from the same Google Places
    # data already on the page (coordinates, google_reviews), not invented. This is what
    # lets Google show a star rating directly in search results for this hotel.
    if ($coordinates -and $coordinates.lat -and $coordinates.lng) {
        $hotelSchema.geo = @{"@type"="GeoCoordinates";latitude=$coordinates.lat;longitude=$coordinates.lng}
    }
    if ($googleReviews -and $googleReviews.rating -and $googleReviews.review_count) {
        $hotelSchema.aggregateRating = @{"@type"="AggregateRating";ratingValue=[double]$googleReviews.rating;reviewCount=[int]$googleReviews.review_count}
    }
    if ($googleReviews -and @($googleReviews.reviews).Count -gt 0) {
        $hotelSchema.review = @(@($googleReviews.reviews) | ForEach-Object {
            @{"@type"="Review";author=@{"@type"="Person";name=[string]$_.author};reviewRating=@{"@type"="Rating";ratingValue=[double]$_.rating};reviewBody=[string]$_.text}
        })
    }

    # Links this page (not the Hotel entity itself -- Wild Papagayo doesn't
    # operate the hotel) to the single site-wide Wild Papagayo organization
    # node, reinforcing the same entity across every page type.
    $hotelWebPage = @{"@type"="WebPage";"@id"="$canon#webpage";url=$canon;name=[string]$hotel.name;publisher=@{"@type"="TravelAgency";"@id"="$siteUrl/#organization";name="Wild Papagayo"}}

    $schemaGraph = @(
        $hotelSchema,
        $hotelWebPage,
        @{"@type"="BreadcrumbList";itemListElement=@(@{"@type"="ListItem";position=1;name="Home";item="$siteUrl/"},@{"@type"="ListItem";position=2;name="Hotels";item="$siteUrl/hotels/"},@{"@type"="ListItem";position=3;name=[string]$hotel.name;item=$canon})}
    )
    if ($faqEntities.Count -gt 0) { $schemaGraph += @{"@type"="FAQPage";mainEntity=$faqEntities} }
    $schema = @{"@context"="https://schema.org";"@graph"=$schemaGraph} | ConvertTo-Json -Depth 10 -Compress

    $ctaText = [Uri]::EscapeDataString("Hello Wild Papagayo! I am staying at $short and would like help with private transportation and tours.")
    $cta = "https://wa.me/50688566325?text=$ctaText"

    # Transportation & Guide Services panel -- replaces the old "Nearby highlights" panel,
    # which only ever rendered a single generic card. Uses real transfer-time data already
    # on the hotel record plus Wild Papagayo's own real service offering (not a third-party
    # claim, so no source verification needed).
    $airportTransferHtml = if ($bothAirportsHtml) { $bothAirportsHtml } else { '<div class="hp-transport-row"><strong>Private Airport Transfer</strong><p>' + (ConvertTo-HtmlSafe $transferLabel) + '</p></div>' }
    $transportPanelHtml = '<div class="hp-nearby-panel"><div class="hp-panel-title">Transportation &amp; Guides</div>' +
        $airportTransferHtml +
        $pickupBlurb +
        $airportBlurb +
        '<div class="hp-transport-row"><strong>Private Driver</strong><p>Door-to-door private transportation for every tour and excursion -- no shared shuttles, no waiting on other guests.</p></div>' +
        '<div class="hp-transport-row"><strong>Certified Local Guides</strong><p>Every experience is led by a bilingual, certified local guide who knows ' + (ConvertTo-HtmlSafe $destinationName) + ' firsthand.</p></div>' +
        '<div style="margin-top:14px;display:flex;gap:10px;flex-wrap:wrap">' +
        '<a class="hp-btn hp-btn-primary" href="../Bookingform.html?service=transportation">Book Private Transport</a>' +
        '<a class="hp-btn hp-btn-outline-navy" href="../Bookingform.html?service=guide">Book a Private Guide</a>' +
        '</div></div>'

    $seoTitleOverride = [string](Get-PropertyValue $hotel "seo_title_override" "")
    $seoTitle = if ($seoTitleOverride) { $seoTitleOverride } elseif ($short -match 'Costa Rica') { "$short Guide | Tours & Transfers" } else { "$short Costa Rica Guide | Tours & Transfers" }
    $seoDescOverride = [string](Get-PropertyValue $hotel "seo_description_override" "")
    $seoDescVariants = @(
        "Plan a stay at $short with airport transfer information, recommended private tours, nearby destinations and local travel advice from Wild Papagayo.",
        "Plan a stay at $short with transfer times, tour recommendations and local travel advice from Wild Papagayo.",
        "Plan your stay at $short with transfers, tours and local travel advice from Wild Papagayo.",
        "Plan your stay at $short with Wild Papagayo's expert local travel advice."
    )
    if ($seoDescOverride -and $seoDescOverride.Length -le 160) {
        $seoDesc = $seoDescOverride
    } else {
        $seoDesc = $seoDescVariants | Where-Object { $_.Length -le 150 } | Select-Object -First 1
        if (-not $seoDesc) { $seoDesc = Get-SeoDescription $seoDescVariants[-1] }
    }

    $officialLine = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$hotel.official_url)) {
        $officialLine = '<p class="hp-official">Hotel details can change. Confirm resort-specific amenities and policies on the <a href="' + (ConvertTo-HtmlSafe $hotel.official_url) + '" target="_blank" rel="noopener">official hotel website</a>.</p>'
    }

    # Expedia affiliate booking button -- only shown once a real per-hotel
    # affiliate link has been added via the CMS. No link, no button/disclosure.
    $expediaLink = [string](Get-PropertyValue $hotel 'expedia_affiliate_link' '')
    $expediaButtonHtml = ''
    $expediaDisclosureHtml = ''
    if (-not [string]::IsNullOrWhiteSpace($expediaLink)) {
        $expediaButtonHtml = '<a class="hp-btn hp-btn-expedia" href="' + (ConvertTo-HtmlSafe $expediaLink) + '" target="_blank" rel="sponsored noopener">Book on Expedia &rarr;</a><span class="hp-paid-link-tag">Paid link</span>'
        $expediaDisclosureHtml = '<p class="hp-expedia-disclosure">Wild Papagayo is an independent travel guide, not an official booking channel for this hotel. If you book through the link above, we will receive a commission based on a percentage of the price -- our opinions about this hotel are entirely our own.</p>'
    }

    # Amenities and room types only come from a real source (URL import) --
    # omit the whole section rather than show an empty/generic placeholder
    # when a hotel was only created by name.
    $amenitiesSection = ''
    $amenityList = @(Get-PropertyValue $hotel 'amenities' @())
    if ($amenityList.Count -gt 0) {
        $amenityItems = ($amenityList | ForEach-Object { '<div class="hp-amenity"><span class="hp-amenity-icon">' + (Get-IconHtml 'nature') + '</span><span>' + (ConvertTo-HtmlSafe $_) + '</span></div>' }) -join ''
        $amenitiesSection = '<section class="hp-section"><div class="hp-wrap"><div class="hp-heading"><div class="hp-eyebrow">On-site</div><h2>Amenities</h2></div><div class="hp-amenity-grid">' + $amenityItems + '</div></div></section>'
    }

    $roomTypesSection = ''
    $roomTypeList = @(Get-PropertyValue $hotel 'room_types' @())
    if ($roomTypeList.Count -gt 0) {
        $roomCards = ($roomTypeList | ForEach-Object {
            $roomName = [string](Get-PropertyValue $_ 'name' '')
            $roomDesc = [string](Get-PropertyValue $_ 'description' '')
            '<article class="hp-room-card"><h3>' + (ConvertTo-HtmlSafe $roomName) + '</h3><p>' + (ConvertTo-HtmlSafe $roomDesc) + '</p></article>'
        }) -join ''
        $roomTypesSection = '<section class="hp-section hp-section-soft"><div class="hp-wrap"><div class="hp-heading"><div class="hp-eyebrow">Where to stay</div><h2>Room &amp; suite types</h2></div><div class="hp-room-grid">' + $roomCards + '</div></div></section>'
    }

    $html = $template
    $map = @{
        '__COMPONENT_HEADER__'=$header
        '__COMPONENT_FOOTER__'=$footer
        '__SEO_TITLE__'=$seoTitle
        '__SEO_DESCRIPTION__'=$seoDesc
        '__CANONICAL__'=$canon
        '__OG_IMAGE__'=$og
        '__SCHEMA__'=$schema
        '__HERO_IMAGE__'=[string]$hotel.hero_image
        '__HERO_IMAGE_ALT__'=(ConvertTo-HtmlSafe ([string](Get-PropertyValue $hotel "hero_image_alt" $hotel.name)))
        '__HOTEL_CATEGORY__'=[string]$hotel.category
        '__LOCATION_LABEL__'=[string]$hotel.location_label
        '__HOTEL_NAME__'=[string]$hotel.name
        '__HERO_DESCRIPTION__'=$heroDescription
        '__HERO_FACTS_STRIP__'=$heroFactsStrip
        '__INSIGHT_RATING_BLOCK__'=$insightRatingBlock
        '__RATING_PANEL_BLOCK__'=$ratingPanelBlock
        '__QUICK_FACTS__'=$factsHtml
        '__AMENITIES_SECTION__'=$amenitiesSection
        '__ROOM_TYPES_SECTION__'=$roomTypesSection
        '__LOVE_CARDS__'=$loveCards
        '__PALM_ICON__'=(Get-IconHtml 'nature')
        '__LOCAL_INSIGHT__'=$localInsight
        '__CURATED_EXPERIENCES_SECTION__'=$curatedExperiencesSectionHtml
        '__EXCURSION_GUIDE_SECTION__'=$excursionGuideSectionHtml
        '__PRIVATE_TOURS_SECTION__'=$privateToursSectionHtml
        '__ITINERARY__'=$itineraryHtml
        '__MAP_EMBED__'=$mapEmbed
        '__MAP_LINK__'=$mapLinkHtml
        '__ADDRESS__'=$addressHtml
        '__BEST_TIME_HTML__'=$bestTimeHtml
        '__RESTAURANTS_SECTION__'=$restaurantsSection
        '__NEARBY_CARDS__'=$nearbyCards
        '__TRANSPORT_PANEL__'=$transportPanelHtml
        '__REVIEWS_SECTION__'=$reviewsSection
        '__ARTICLE_CARDS__'=$articleCards
        '__FAQ_BLOCK__'=$faqHtml
        '__OFFICIAL_URL__'=[string]$hotel.official_url
        '__OFFICIAL_LINE__'=$officialLine
        '__HOTEL_SHORT_NAME__'=$short
        '__CTA_URL__'=$cta
        '__EXPEDIA_BUTTON__'=$expediaButtonHtml
        '__EXPEDIA_DISCLOSURE__'=$expediaDisclosureHtml
        '__WHY_STAY_HERE__'=$WhyStayHere
        '__EXPERIENCE_HIGHLIGHTS__'=$highlightsHtml
        '__LOCAL_TIPS__'=$localTipsHtml
        '__SUGGESTED_STAY__'=$suggestedStayHtml
    }
    foreach ($key in $map.Keys) { $html = $html.Replace($key,[string]$map[$key]) }

    Write-FileIfChanged -Path (Join-Path $outDir "$slug.html") -Content $html
    Write-Host "Generated premium hotel: hotels/$slug.html"
    $generated++
}

Write-Host "Premium Hotel Engine complete: $generated page(s)." -ForegroundColor Green
if ($warnings.Count -gt 0) { foreach ($w in $warnings) { Write-Warning $w } }
exit 0

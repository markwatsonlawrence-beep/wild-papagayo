# ============================================================
# Wild Papagayo - Hotel Import from URL v1.0
# Fetches a hotel's official page, extracts its text, and asks
# Claude (Anthropic API) to read it and fill in real brand,
# category, luxury_level, descriptions and FAQ -- instead of the
# generic placeholders hotel-autofill.ps1 uses when there's no
# source page at all.
# Usage: .\hotel-import-url.ps1 -Url "https://..." [-HotelName "..."]
# Requires ANTHROPIC_API_KEY in wild-papagayo\.env
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Url,
    [string]$HotelName
)

$ErrorActionPreference = 'Stop'
# Output gets captured by the parent process via `2>&1 | Out-String`; force
# UTF-8 console output or accented characters get mis-encoded in transit.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = $PSScriptRoot

function Read-EnvFile {
    param([string]$Path)
    $vars = @{}
    if (-not (Test-Path $Path)) { return $vars }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
            $vars[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $vars
}

$envVars = Read-EnvFile (Join-Path $root '.env')
$apiKey = $envVars['ANTHROPIC_API_KEY']
if ([string]::IsNullOrWhiteSpace($apiKey)) { $apiKey = $env:ANTHROPIC_API_KEY }
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'ANTHROPIC_API_KEY not found. Add it to wild-papagayo\.env' }

# --- 1. Fetch the page -------------------------------------------------
Write-Host ''
Write-Host "Fetching: $Url" -ForegroundColor Cyan
$headers = @{ 'User-Agent' = 'Mozilla/5.0 (compatible; WildPapagayoImportBot/1.0; +https://wildpapagayo.com)' }
$response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers $headers -TimeoutSec 45 -MaximumRedirection 8
# Invoke-WebRequest often mis-detects the page's encoding (falls back to
# ISO-8859-1) when the server's Content-Type header omits charset. Decode
# the raw bytes as UTF-8 explicitly -- the vast majority of hotel sites
# serve UTF-8 even when they forget to say so in the header.
$rawBytes = $response.RawContentStream.ToArray()
$html = [System.Text.Encoding]::UTF8.GetString($rawBytes)

function Get-MetaValue {
    param([string]$Html, [string]$Name)
    $m = [regex]::Match($Html, "<meta[^>]+(?:name|property)=[""']$Name[""'][^>]+content=[""']([^""']*)[""']", 'IgnoreCase')
    if ($m.Success) { return [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value) }
    return ''
}
function Get-PageTitle {
    param([string]$Html)
    $m = [regex]::Match($Html, '<title[^>]*>([^<]*)</title>', 'IgnoreCase')
    if ($m.Success) { return [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value.Trim()) }
    return ''
}
function Get-PlainText {
    param([string]$Html, [int]$MaxChars = 12000)
    $text = $Html
    $text = [regex]::Replace($text, '(?is)<script.*?</script>', ' ')
    $text = [regex]::Replace($text, '(?is)<style.*?</style>', ' ')
    $text = [regex]::Replace($text, '(?is)<(h1|h2|h3|p|li|br|/tr)[^>]*>', "`n")
    $text = [regex]::Replace($text, '(?is)<[^>]+>', ' ')
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $text = [regex]::Replace($text, '[ \t]+', ' ')
    $text = [regex]::Replace($text, '\n\s*\n+', "`n")
    $text = $text.Trim()
    if ($text.Length -gt $MaxChars) { $text = $text.Substring(0, $MaxChars) }
    return (Repair-Utf8String $text)
}

function Repair-Utf8String {
    # Scraped pages sometimes carry lone/unpaired UTF-16 surrogate characters
    # (broken encoding on the source site). Those can't be represented in
    # valid UTF-8 and the Anthropic API rejects the whole request body if
    # any slip through. Round-tripping through UTF8Encoding's byte
    # conversion replaces anything invalid with a safe placeholder.
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $utf8 = New-Object System.Text.UTF8Encoding($false, $false)
    $bytes = $utf8.GetBytes($Text)
    return $utf8.GetString($bytes)
}

$pageTitle = Repair-Utf8String (Get-PageTitle $html)
$metaDescription = Repair-Utf8String (Get-MetaValue $html 'description')
$plainText = Get-PlainText $html

if ([string]::IsNullOrWhiteSpace($HotelName)) {
    # Split only on a "|" or a dash/en-dash/em-dash surrounded by whitespace (a real
    # title separator, e.g. "Hotel Name - Site Name"). A plain hyphen with no spaces
    # around it is almost always part of the name itself (e.g. "Ritz-Carlton",
    # "All-Inclusive") and must not be treated as a separator.
    $HotelName = ($pageTitle -split '\s[-\u2013\u2014]\s|\|')[0].Trim()
    if ([string]::IsNullOrWhiteSpace($HotelName)) { throw 'Could not determine a hotel name from the page title. Pass -HotelName explicitly.' }
}

Write-Host "Detected name: $HotelName" -ForegroundColor DarkGray
Write-Host "Page text: $($plainText.Length) chars" -ForegroundColor DarkGray

# --- 2. Create the base hotel record ------------------------------------
$createOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'hotel-create.ps1') -HotelName $HotelName 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "hotel-create.ps1 failed: $createOut" }
if ($createOut -notmatch '"id"\s*:\s*"([^"]+)"') { throw "Could not parse hotel id from create output: $createOut" }
$hotelId = $Matches[1]
$masterPath = Join-Path $root "knowledge\master\hotels\$hotelId.json"

# --- 3. Ask Claude to read the page text and fill real fields -----------
Write-Host "Asking Claude to read the page and extract hotel details..." -ForegroundColor Cyan

$schema = [ordered]@{
    type = 'object'
    properties = [ordered]@{
        hotel_name = @{ type = 'string'; description = 'The hotel''s real, proper name exactly as it would be booked or referred to by a guest, e.g. "Suitree Experience Hotel", "Four Seasons Resort Costa Rica". This is NOT the page title tag and must not include marketing taglines, SEO keyword-stuffing, or phrases like "in Costa Rica" / "Luxury Retreat" unless those words are genuinely part of the brand name itself.' }
        brand = @{ type = 'string'; description = 'Hotel brand or management group, e.g. "Marriott", "Andaz by Hyatt". Use the hotel name itself if independent/no chain brand is evident.' }
        category = @{ type = 'string'; description = 'Short category label, e.g. "Luxury Beach Resort", "Boutique Hotel", "All-Inclusive Resort"' }
        luxury_level = @{ type = 'string'; enum = @('Luxury','Upscale','Boutique','Standard','Ultra Luxury') }
        description = @{ type = 'string'; description = 'Editorial description, 2-3 sentences, 80-400 characters, written for a travel guide (not marketing copy from the source page verbatim)' }
        hero_description = @{ type = 'string'; description = 'One short sentence for a hero banner' }
        local_take = @{ type = 'string'; description = 'One to two sentences of local travel-advisor style insight about who this hotel suits' }
        location_label = @{ type = 'string'; description = 'The town, city, or named area where this hotel is actually located, e.g. "Monteverde", "Playa Tamarindo", "La Fortuna". Must come from the page text, not assumed.' }
        province = @{ type = 'string'; description = 'Costa Rican province, e.g. "Guanacaste", "Puntarenas", "Alajuela", "San Jose"' }
        nearest_airport = @{ type = 'string'; enum = @('lir','sjo'); description = '"lir" for Guanacaste Airport (Liberia) if this location is in Guanacaste/northern Pacific; "sjo" for Juan Santamaria International (San Jose) if it is more central, Monteverde, Arenal, or elsewhere commonly reached via San Jose.' }
        transfer_description = @{ type = 'string'; description = 'One sentence describing typical private transfer time from the nearest airport to this hotel, e.g. "Approximately 3 hours from San Jose (SJO)."' }
        amenities = @{
            type = 'array'
            description = 'Real, specific amenities mentioned on the page -- e.g. "Infinity pool", "On-site spa", "Farm-to-table restaurant". 4 to 10 items. Do not include generic filler like "WiFi" unless it is genuinely notable. Empty array if the page does not describe any.'
            items = @{ type = 'string' }
        }
        room_types = @{
            type = 'array'
            description = 'Real room/suite/villa categories mentioned on the page, each with a one-sentence description. Empty array if the page does not describe distinct room types.'
            items = @{
                type = 'object'
                properties = @{ name = @{type='string'}; description = @{type='string'} }
                required = @('name','description')
                additionalProperties = $false
            }
        }
        traveler_profiles = @{
            type = 'array'
            description = 'Exactly 3 traveler types this SPECIFIC hotel genuinely suits, grounded in what the page actually describes (its amenities, setting, room types, activities) -- not generic categories. Each needs a short profile label (2-4 words, e.g. "Wellness Travelers", "Multigenerational Families") and a one-sentence reason tied to real details from the page.'
            items = @{
                type = 'object'
                properties = @{ profile = @{type='string'}; reason = @{type='string'} }
                required = @('profile','reason')
                additionalProperties = $false
            }
        }
        faq = @{
            type = 'array'
            items = @{
                type = 'object'
                properties = @{ q = @{type='string'}; a = @{type='string'} }
                required = @('q','a')
                additionalProperties = $false
            }
        }
    }
    required = @('hotel_name','brand','category','luxury_level','description','hero_description','local_take','location_label','province','nearest_airport','transfer_description','amenities','room_types','traveler_profiles','faq')
    additionalProperties = $false
}

$userPrompt = @"
Source URL: $Url
Page title: $pageTitle
Meta description: $metaDescription

Extracted page text:
---
$plainText
---

Read the page text above and extract real, grounded details about this hotel for a Costa Rica travel guide entry. Do not invent facts the page doesn't support -- if something isn't in the text, give your best reasonable editorial judgment based on what IS there (e.g. infer luxury_level from amenities/description tone), but do not fabricate specific amenities, prices, or awards that aren't mentioned. The "faq" array must contain exactly 3 items.
"@

$requestBody = [ordered]@{
    model = 'claude-opus-4-8'
    max_tokens = 2048
    messages = @(
        [ordered]@{ role = 'user'; content = $userPrompt }
    )
    output_config = [ordered]@{
        format = [ordered]@{ type = 'json_schema'; schema = $schema }
    }
} | ConvertTo-Json -Depth 20
# Invoke-RestMethod does not reliably send [string] bodies as UTF-8 on
# Windows PowerShell 5.1 -- any accented/curly characters scraped from the
# page get mangled in transit. Encode to UTF-8 bytes explicitly instead.
$requestBytes = [System.Text.Encoding]::UTF8.GetBytes($requestBody)

$apiHeaders = @{
    'x-api-key' = $apiKey
    'anthropic-version' = '2023-06-01'
}

try {
    # Invoke-RestMethod's automatic response parsing has the same mis-decoding
    # problem in reverse -- use Invoke-WebRequest and decode the raw response
    # bytes as UTF-8 ourselves before handing the JSON to ConvertFrom-Json.
    $webResponse = Invoke-WebRequest -Uri 'https://api.anthropic.com/v1/messages' -Method Post -Headers $apiHeaders -Body $requestBytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 90 -UseBasicParsing
    $responseText = [System.Text.Encoding]::UTF8.GetString($webResponse.RawContentStream.ToArray())
    $result = $responseText | ConvertFrom-Json
} catch {
    $resp = $_.Exception.Response
    if ($resp) {
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $errorBody = $reader.ReadToEnd()
        throw "Claude API error: $errorBody"
    }
    throw
}
$textBlock = $result.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1
if (-not $textBlock) { throw "No text content in Claude response: $($result | ConvertTo-Json -Depth 10 -Compress)" }
$extracted = $textBlock.text | ConvertFrom-Json

# --- 4. Merge into the master record -------------------------------------
$Hotel = [System.IO.File]::ReadAllText($masterPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
# Claude read the full page and can identify the real hotel name even when the
# page <title> tag is an SEO/marketing string with no clean separator to split on
# (the earlier regex-only approach kept the whole messy title in that case).
$realName = [string]$extracted.hotel_name
if (-not [string]::IsNullOrWhiteSpace($realName)) {
    $Hotel.identity.official_name = $realName
    $Hotel.identity.display_name = $realName
}
$Hotel.identity.brand = [string]$extracted.brand
$Hotel.identity.category = [string]$extracted.category
$Hotel.identity.luxury_level = [string]$extracted.luxury_level
$Hotel.editorial.description = [string]$extracted.description
$Hotel.editorial.hero_description = [string]$extracted.hero_description
$Hotel.wild_insights.local_take = [string]$extracted.local_take
$Hotel.faq = @($extracted.faq | ForEach-Object { [pscustomobject]@{ q = [string]$_.q; a = [string]$_.a } })
$Hotel | Add-Member -NotePropertyName 'amenities' -NotePropertyValue (@($extracted.amenities | ForEach-Object { [string]$_ })) -Force
$Hotel | Add-Member -NotePropertyName 'room_types' -NotePropertyValue (@($extracted.room_types | ForEach-Object { [pscustomobject]@{ name = [string]$_.name; description = [string]$_.description } })) -Force
$Hotel.traveler_profiles = @($extracted.traveler_profiles | ForEach-Object { [string]$_.profile })
$Hotel | Add-Member -NotePropertyName 'traveler_profile_reasons' -NotePropertyValue (@($extracted.traveler_profiles | ForEach-Object { [pscustomobject]@{ profile = [string]$_.profile; reason = [string]$_.reason } })) -Force

# --- Location: match the real place name Claude extracted against the
# destinations knowledge graph, instead of leaving the hotel-create.ps1
# "papagayo" default in place for hotels that aren't actually in Papagayo.
$locationLabel = [string]$extracted.location_label
$matchedDestinationId = $null
$destinationsGraphPath = Join-Path $root 'knowledge\destinations.json'
if (Test-Path $destinationsGraphPath) {
    $destGraph = [System.IO.File]::ReadAllText($destinationsGraphPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $needle = $locationLabel.ToLowerInvariant()
    $match = $destGraph | Where-Object {
        $_.name.ToLowerInvariant() -eq $needle -or
        (@($_.aliases) | Where-Object { $_.ToLowerInvariant() -eq $needle }).Count -gt 0 -or
        $needle.Contains($_.name.ToLowerInvariant())
    } | Select-Object -First 1
    if ($match) { $matchedDestinationId = [string]$match.id }
}

if ($matchedDestinationId) { $Hotel.location.destination_id = $matchedDestinationId }
else { $Hotel.location.destination_id = '' }  # honest "unmatched" rather than a wrong default
$Hotel.location.location_label = $locationLabel
$Hotel.location.province = [string]$extracted.province
$Hotel.location.airport_id = [string]$extracted.nearest_airport
$Hotel.location.transfer.label = [string]$extracted.transfer_description
$Hotel.location.transfer.source_type = 'claude_estimate_from_official_source'
$Hotel.official_sources = @([ordered]@{ source_id = 'official-import'; type = 'official'; url = $Url })
$Hotel.verification.status = 'unverified'
$Hotel.verification.official_source = $Url
$Hotel.verification.note = 'Imported from official source URL and summarized by Claude. Facts should still be human-reviewed before publication.'

$json = $Hotel | ConvertTo-Json -Depth 15
[System.IO.File]::WriteAllText($masterPath, $json, [System.Text.UTF8Encoding]::new($false))

# Automatic photo sourcing via hotel-photo-finder.ps1 (Google Places Photos) is
# intentionally disabled here -- this project had a real legal issue from using
# third-party-sourced photos before, and photos had to be removed as a result.
# Hero images must be added manually with owned/licensed/explicitly authorized
# imagery. Run hotel-photo-finder.ps1 by hand only if you have confirmed the
# photo source is legally usable.
Write-Host "  Hero image left as generic placeholder -- add a real, licensed photo manually." -ForegroundColor DarkYellow

Write-Host ''
Write-Host 'Hotel imported and enriched from URL.' -ForegroundColor Green
Write-Host "  id: $hotelId"
[pscustomobject]@{ id = $hotelId; path = $masterPath } | ConvertTo-Json -Compress

# ============================================================
# Wild Papagayo - Question Analyze v1.0
# Takes raw traveler-question text (pasted from Facebook, Reddit,
# TripAdvisor, WhatsApp, etc.) and asks Claude to detect intent,
# knowledge-graph tags (destinations/hotels/tours/activities/
# seasons/traveler profiles/transportation), priority, and a
# suggested title/slug/FAQ -- grounded against the REAL ids that
# already exist in the knowledge graph, not invented ones.
# Output-only: does not write to questions.json. Pair with
# question-save.ps1 to persist after human review.
# Usage: .\question-analyze.ps1 -QuestionText "..." [-Source "facebook"]
# Requires ANTHROPIC_API_KEY in wild-papagayo\.env
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$QuestionText,
    [string]$Source = 'facebook'
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

function Read-Utf8Json([string]$path) { return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }

# --- 1. Load the real knowledge-graph id lists so Claude can only pick
#        ids that actually exist, instead of inventing new ones. ----------
$destinations = @(Read-Utf8Json (Join-Path $root 'knowledge\destinations.json')) | ForEach-Object { $_.id }
$activities = @(Read-Utf8Json (Join-Path $root 'knowledge\activities.json')) | ForEach-Object { $_.id }
$transportation = @(Read-Utf8Json (Join-Path $root 'knowledge\transportation.json')) | ForEach-Object { $_.id }
$travelerProfiles = @(Read-Utf8Json (Join-Path $root 'knowledge\traveler-profiles.json')) | ForEach-Object { $_.id }
$seasons = @(Read-Utf8Json (Join-Path $root 'knowledge\seasons.json')) | ForEach-Object { $_.id }

$toursDir = Join-Path $root 'knowledge\tours'
$tourLines = Get-ChildItem $toursDir -Filter '*.json' -File | ForEach-Object {
    $t = Read-Utf8Json $_.FullName
    "$($t.id) :: $($t.name)"
}
$tourIds = @($tourLines | ForEach-Object { ($_ -split ' :: ')[0] })

$hotelsDir = Join-Path $root 'knowledge\master\hotels'
$hotelLines = Get-ChildItem $hotelsDir -Filter '*.json' -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' } | ForEach-Object {
    $h = Read-Utf8Json $_.FullName
    $label = if ($h.identity.display_name) { $h.identity.display_name } else { $h.identity.official_name }
    "$($h.identity.id) :: $label"
}
$hotelIds = @($hotelLines | ForEach-Object { ($_ -split ' :: ')[0] })

# --- 2. Ask Claude to detect + tag ---------------------------------------
Write-Host 'Analyzing question with Claude...' -ForegroundColor Cyan

$schema = [ordered]@{
    type = 'object'
    properties = [ordered]@{
        working_title = @{ type = 'string'; description = 'A compelling, SEO-friendly article title that would answer this question, 40-70 characters' }
        intent = @{ type = 'string'; enum = @('informational','commercial-investigation','transactional','navigational') }
        content_type = @{ type = 'string'; enum = @('comparison-guide','itinerary-guide','how-to-guide','faq-guide','destination-guide','logistics-guide') }
        destination_ids = @{ type = 'array'; items = @{ type = 'string'; enum = $destinations }; description = 'Only ids that are genuinely relevant to this question. Empty array if none apply.' }
        hotel_ids = @{ type = 'array'; items = @{ type = 'string'; enum = $hotelIds }; description = 'Only ids explicitly named or clearly implied. Empty array if none apply.' }
        tour_ids = @{ type = 'array'; items = @{ type = 'string'; enum = $tourIds } }
        activity_ids = @{ type = 'array'; items = @{ type = 'string'; enum = $activities } }
        season_ids = @{ type = 'array'; items = @{ type = 'string'; enum = $seasons } }
        traveler_profile_ids = @{ type = 'array'; items = @{ type = 'string'; enum = $travelerProfiles } }
        transportation_ids = @{ type = 'array'; items = @{ type = 'string'; enum = $transportation } }
        seo_potential = @{ type = 'integer'; description = 'Estimated search-demand/SEO value 0-100' }
        competition = @{ type = 'string'; enum = @('Low','Medium','High'); description = 'Estimated competitiveness of ranking for this topic' }
        commercial_intent = @{ type = 'string'; enum = @('Low','Medium','High'); description = 'How likely this content is to drive a booking inquiry' }
        priority = @{ type = 'integer'; description = '0-100 overall priority combining SEO potential, low competition and commercial intent' }
        suggested_seo_title = @{ type = 'string'; description = 'Under 60 characters' }
        suggested_seo_description = @{ type = 'string'; description = 'Under 155 characters' }
        suggested_slug = @{ type = 'string'; description = 'lowercase-hyphenated-slug, no special characters' }
        suggested_faq = @{
            type = 'array'
            description = 'Exactly 3 short related FAQ questions (no answers) a traveler asking this would also want covered'
            items = @{ type = 'string' }
        }
        business_goal = @{ type = 'string'; description = 'One sentence on what booking/inquiry behavior this article should drive' }
        notes = @{ type = 'string'; description = 'One sentence of editorial guidance for whoever writes this' }
    }
    required = @('working_title','intent','content_type','destination_ids','hotel_ids','tour_ids','activity_ids','season_ids','traveler_profile_ids','transportation_ids','seo_potential','competition','commercial_intent','priority','suggested_seo_title','suggested_seo_description','suggested_slug','suggested_faq','business_goal','notes')
    additionalProperties = $false
}

$userPrompt = @"
Real traveler question (source: $Source):
---
$QuestionText
---

You are the content-intelligence layer for Wild Papagayo, a private tour and transfer company operating in Guanacaste and Arenal, Costa Rica. Analyze this real traveler question and tag it against the ACTUAL knowledge graph ids below -- do not invent ids that are not in these lists, and only include ids that are genuinely relevant to this specific question. Leave arrays empty rather than guessing.

Valid destination ids: $($destinations -join ', ')
Valid tour ids (id :: name): $($tourLines -join ' | ')
Valid hotel ids (id :: name): $($hotelLines -join ' | ')
Valid activity ids: $($activities -join ', ')
Valid season ids (months + dry-season/green-season groups): $($seasons -join ', ')
Valid traveler profile ids: $($travelerProfiles -join ', ')
Valid transportation ids: $($transportation -join ', ')
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
$requestBytes = [System.Text.Encoding]::UTF8.GetBytes($requestBody)

$apiHeaders = @{
    'x-api-key' = $apiKey
    'anthropic-version' = '2023-06-01'
}

try {
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

$output = [ordered]@{
    question = $QuestionText
    source = $Source
    working_title = $extracted.working_title
    intent = $extracted.intent
    content_type = $extracted.content_type
    destination_ids = @($extracted.destination_ids)
    hotel_ids = @($extracted.hotel_ids)
    tour_ids = @($extracted.tour_ids)
    activity_ids = @($extracted.activity_ids)
    season_ids = @($extracted.season_ids)
    traveler_profile_ids = @($extracted.traveler_profile_ids)
    transportation_ids = @($extracted.transportation_ids)
    seo_potential = $extracted.seo_potential
    competition = $extracted.competition
    commercial_intent = $extracted.commercial_intent
    priority = $extracted.priority
    suggested_seo_title = $extracted.suggested_seo_title
    suggested_seo_description = $extracted.suggested_seo_description
    suggested_slug = $extracted.suggested_slug
    suggested_faq = @($extracted.suggested_faq)
    business_goal = $extracted.business_goal
    notes = $extracted.notes
}
$output | ConvertTo-Json -Depth 10 -Compress

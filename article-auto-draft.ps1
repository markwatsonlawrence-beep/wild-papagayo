# ============================================================
# Wild Papagayo - Article Auto-Draft v1.0
# Takes an in-progress article record (title, category, and any
# tagged tour_ids/hotel_ids/destination_ids) and asks Claude to
# write the real content_block_1/2/3, FAQ, travel tip, excerpt
# and SEO fields -- grounded ONLY in the real facts pulled from
# the linked hotel/tour/destination knowledge records, matching
# the site's no-fabrication policy (no invented prices, hours,
# or specifics not present in the source data).
# Output-only: writes the updated article JSON to <ArticleJsonPath>.result.json
# using explicit UTF-8 file I/O. Does not write to blog-data.json. A result
# file is used instead of stdout because Windows PowerShell 5.1's subprocess
# stdout capture (`2>&1 | Out-String`) does not reliably preserve accented
# characters in transit between processes, regardless of console encoding
# settings on either side -- writing bytes directly to disk sidesteps that
# whole class of bug.
# Usage: .\article-auto-draft.ps1 -ArticleJsonPath "C:\...\temp.json"
# Requires ANTHROPIC_API_KEY in wild-papagayo\.env
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ArticleJsonPath
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Read-EnvFile {
    param([string]$Path)
    $vars = @{}
    if (-not (Test-Path $Path)) { return $vars }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') { $vars[$Matches[1]] = $Matches[2].Trim() }
    }
    return $vars
}

$envVars = Read-EnvFile (Join-Path $root '.env')
$apiKey = $envVars['ANTHROPIC_API_KEY']
if ([string]::IsNullOrWhiteSpace($apiKey)) { $apiKey = $env:ANTHROPIC_API_KEY }
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'ANTHROPIC_API_KEY not found. Add it to wild-papagayo\.env' }

function Read-Utf8Json([string]$path) { return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }
function Read-Utf8JsonSafe([string]$path) {
    # A tagged hotel/tour/destination id that no longer has a matching knowledge
    # file (renamed, removed, or a stale tag) must not crash the whole draft --
    # skip that one grounding fact and keep going, same "honest degradation"
    # policy used everywhere else on the site.
    if (-not (Test-Path $path)) { return $null }
    try { return Read-Utf8Json $path } catch { return $null }
}

if (-not (Test-Path $ArticleJsonPath)) { throw "Article JSON file not found: $ArticleJsonPath" }
$article = Read-Utf8Json $ArticleJsonPath

$title = [string]$article.title
$category = [string]$article.category
if ([string]::IsNullOrWhiteSpace($title)) { throw 'Article must have a title before drafting.' }

# --- 1. Gather real grounding facts from whatever this article is tagged to ---
$factsLines = New-Object System.Collections.Generic.List[string]

foreach ($id in @($article.destination_ids)) {
    $d = Read-Utf8JsonSafe (Join-Path $root "knowledge\destinations\$id.json")
    if ($d) {
        $factsLines.Add("DESTINATION: $($d.name) -- $($d.summary)")
        if ($d.best_season) { $factsLines.Add("  Best season: $($d.best_season)") }
        if ($d.wildlife) { $factsLines.Add("  Real wildlife: " + (($d.wildlife | ForEach-Object { $_.name }) -join ', ')) }
        if ($d.restaurants) { $factsLines.Add("  Real restaurants: " + (($d.restaurants | Select-Object -First 5 | ForEach-Object { $_.name }) -join ', ')) }
    }
}
foreach ($id in @($article.hotel_ids)) {
    $h = Read-Utf8JsonSafe (Join-Path $root "knowledge\hotels\$id.json")
    if ($h) {
        $factsLines.Add("HOTEL: $($h.name) ($($h.category), $($h.location_label))")
        if ($h.amenities) { $factsLines.Add("  Real amenities: " + (($h.amenities | Select-Object -First 8) -join ', ')) }
        if ($h.transfer_minutes) { $factsLines.Add("  Real transfer time: $($h.transfer_minutes.label)") }
        if ($h.google_reviews) { $factsLines.Add("  Real Google rating: $($h.google_reviews.rating)/5 ($($h.google_reviews.review_count) reviews)") }
    }
}
foreach ($id in @($article.tour_ids)) {
    $t = Read-Utf8JsonSafe (Join-Path $root "knowledge\tours\$id.json")
    if ($t) {
        $factsLines.Add("TOUR: $($t.name) ($($t.duration_label), $($t.difficulty)) -- $($t.short_description)")
        # page_content.everything_included is the single canonical inclusions
        # list (same one the public tour page renders) -- the old top-level
        # `included` field this used to read has been retired.
        if ($t.page_content.everything_included) { $factsLines.Add("  Real inclusions: " + (($t.page_content.everything_included) -join ', ')) }
    }
}

$facts = if ($factsLines.Count -gt 0) { $factsLines -join "`n" } else { '(No hotels, tours or destinations are tagged to this article yet -- write general, honest Guanacaste travel-planning guidance for this topic without inventing specific named entities, prices, or hours.)' }

# --- 1b. Tell Claude what's already published, so it doesn't unknowingly
# rehash an existing article's angle (this is how two near-duplicate "best
# tours from X hotel" articles slipped through before this was added --
# Claude had no way to know the first one existed). -----------------------
$existingTitlesBlock = '(No other articles are published yet.)'
$blogDataPath = Join-Path $root 'blog-data.json'
if (Test-Path $blogDataPath) {
    $ownSlug = [string]$article.slug
    $published = @(Read-Utf8JsonSafe $blogDataPath)
    if ($published) {
        $titles = @($published | Where-Object { [string]$_.slug -ne $ownSlug } | ForEach-Object { "- $($_.title)" })
        if ($titles.Count -gt 0) { $existingTitlesBlock = $titles -join "`n" }
    }
}

Write-Host "Grounding facts gathered: $($factsLines.Count) line(s)" -ForegroundColor Cyan
Write-Host "Asking Claude to write the article..." -ForegroundColor Cyan

$schema = [ordered]@{
    type = 'object'
    properties = [ordered]@{
        excerpt = @{ type = 'string'; description = 'One or two sentences summarizing the article, 100-180 characters, written in a direct local-expert voice (not generic marketing).' }
        seo_title_pro = @{ type = 'string'; description = 'SEO title WITHOUT the " | Wild Papagayo" suffix (that gets appended automatically), 40-60 characters, no truncation marks.' }
        seo_description = @{ type = 'string'; description = 'Meta description, 120-155 characters, no truncation marks.' }
        seo_keywords = @{ type = 'string'; description = 'Comma-separated list of 4-6 relevant SEO keywords.' }
        content_block_1 = @{ type = 'string'; description = 'HTML: one <h2> heading followed by 1-2 <p> paragraphs answering the traveler''s main question on this topic, then a second <h2> with 1 <p> giving the Wild Papagayo recommendation. Use only the real facts provided -- never invent prices, hours, or specific claims not given.' }
        content_block_2 = @{ type = 'string'; description = 'HTML: one <h2> heading ("How to Plan It Well" style) with 1-2 <p> paragraphs, followed by a <blockquote> containing <strong>Local Expert Tip</strong><br> and one specific, genuinely useful tip grounded in the real facts.' }
        content_block_3 = @{ type = 'string'; description = 'HTML: one <h2> heading ("Our Bottom Line" style) with 1 <p> paragraph giving a clear, honest recommendation.' }
        content_block_faq = @{ type = 'string'; description = 'HTML: one <h2>Frequently Asked Questions</h2> followed by exactly 3 <h3> questions each with a <p> answer, grounded in the real facts, at least 180 characters total.' }
        travel_tip = @{ type = 'string'; description = 'One specific, genuinely useful local tip (not the same one used in content_block_2), plain text, 1-2 sentences.' }
        quick_facts = @{
            type = 'array'
            description = '3-5 short factual bullet points readers can scan quickly, each grounded in the real facts provided (e.g. real transfer times, real ratings). Empty array if there are not enough real facts to support any.'
            items = @{ type = 'string' }
        }
    }
    required = @('excerpt','seo_title_pro','seo_description','seo_keywords','content_block_1','content_block_2','content_block_3','content_block_faq','travel_tip','quick_facts')
    additionalProperties = $false
}

$userPrompt = @"
Article title: $title
Category: $category

Real facts available for this article (from Wild Papagayo's own knowledge base -- these are the ONLY specific facts you may cite; do not invent prices, opening hours, distances, or other specifics beyond what's listed here):
---
$facts
---

Articles already published on the Wild Papagayo blog (do not repeat one of these -- if this article's title covers essentially the same question or angle as one of them, write it from a genuinely different, non-overlapping angle instead of restating it):
---
$existingTitlesBlock
---

Write this Wild Papagayo blog article. Wild Papagayo is a private Costa Rica tour and travel-planning company based in Guanacaste. The voice is that of a real local expert who has actually arranged this kind of trip for guests -- direct, honest, and specific, never generic marketing filler. If a claim isn't backed by the real facts above, either omit it or phrase it as general, non-specific travel advice rather than presenting it as a verified fact.
"@

$requestBody = [ordered]@{
    model = 'claude-opus-4-8'
    max_tokens = 4096
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
    $webResponse = Invoke-WebRequest -Uri 'https://api.anthropic.com/v1/messages' -Method Post -Headers $apiHeaders -Body $requestBytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 120 -UseBasicParsing
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
$drafted = $textBlock.text | ConvertFrom-Json

# --- 2. Merge into the article record, leaving anything the user already
# filled in for title/slug/images/links/CTA untouched. -------------------
$article | Add-Member -MemberType NoteProperty -Name 'excerpt' -Value ([string]$drafted.excerpt) -Force
$article | Add-Member -MemberType NoteProperty -Name 'seo_title_pro' -Value ([string]$drafted.seo_title_pro) -Force
$article | Add-Member -MemberType NoteProperty -Name 'seo_description' -Value ([string]$drafted.seo_description) -Force
$article | Add-Member -MemberType NoteProperty -Name 'seo_keywords' -Value ([string]$drafted.seo_keywords) -Force
$article | Add-Member -MemberType NoteProperty -Name 'content_block_1' -Value ([string]$drafted.content_block_1) -Force
$article | Add-Member -MemberType NoteProperty -Name 'content_block_2' -Value ([string]$drafted.content_block_2) -Force
$article | Add-Member -MemberType NoteProperty -Name 'content_block_3' -Value ([string]$drafted.content_block_3) -Force
$article | Add-Member -MemberType NoteProperty -Name 'content_block_faq' -Value ([string]$drafted.content_block_faq) -Force
$article | Add-Member -MemberType NoteProperty -Name 'travel_tip' -Value ([string]$drafted.travel_tip) -Force
$article | Add-Member -MemberType NoteProperty -Name 'quick_facts' -Value (@($drafted.quick_facts | ForEach-Object { [string]$_ })) -Force

$resultPath = "$ArticleJsonPath.result.json"
$resultJson = $article | ConvertTo-Json -Depth 30
[System.IO.File]::WriteAllText($resultPath, $resultJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Draft complete. Result written to: $resultPath" -ForegroundColor Green

# ============================================================
# Wild Papagayo - Question Article Writer v1.0
# Takes one "idea"-status entry from questions/questions.json
# (a real traveler question with no article yet) and asks
# Claude to write a grounded short-form answer article, using
# only the structured Wild Papagayo context already attached to
# the question (linked hotels/tours/destinations) -- not
# invented facts. Appends the result to blog-data.json as a
# draft-ready article; run blog-generator.ps1 afterward to
# publish the HTML.
# Usage: .\question-article-writer.ps1 -QuestionId "q-uber-at-liberia-airport"
# Requires ANTHROPIC_API_KEY in wild-papagayo\.env
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$QuestionId
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

function Repair-Utf8String {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $utf8 = New-Object System.Text.UTF8Encoding($false, $false)
    return $utf8.GetString($utf8.GetBytes($Text))
}

# --- 1. Load the question ---
$questionsPath = Join-Path $root 'questions\questions.json'
$questions = [System.IO.File]::ReadAllText($questionsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$q = $questions | Where-Object { $_.id -eq $QuestionId } | Select-Object -First 1
if (-not $q) { throw "Question not found: $QuestionId" }
if ($q.status -eq 'published' -and $q.article_slug) { throw "Question '$QuestionId' is already published as '$($q.article_slug)'." }

# --- 2. Gather Wild Papagayo context already linked to the question ---
function Get-Names {
    param([string]$Dir, [string[]]$Ids)
    $names = @()
    foreach ($id in @($Ids)) {
        $p = Join-Path $root "$Dir\$id.json"
        if (Test-Path $p) {
            $item = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            $name = if ($item.name) { [string]$item.name } elseif ($item.identity.display_name) { [string]$item.identity.display_name } else { $id }
            $names += $name
        } else { $names += $id }
    }
    return $names
}
$destNames = Get-Names 'knowledge\destinations' $q.destination_ids
$tourNames = Get-Names 'knowledge\tours' $q.tour_ids
$hotelNames = @($q.hotel_ids)

$existingSlugs = @()
$blogPath = Join-Path $root 'blog-data.json'
$blogRaw = [System.IO.File]::ReadAllText($blogPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$articles = if ($blogRaw -is [array]) { @($blogRaw) } else { @($blogRaw.articles) }
$existingSlugs = @($articles | ForEach-Object { $_.slug })
$transferArticle = @($articles | Where-Object { $_.slug -match 'airport-transfer' } | Select-Object -First 1 -ExpandProperty slug)

# --- 3. Ask Claude to write the article ---
$schema = [ordered]@{
    type = 'object'
    properties = [ordered]@{
        title = @{ type = 'string'; description = 'Article headline, under 65 characters, matching search intent' }
        excerpt = @{ type = 'string'; description = '1-2 sentence summary, at least 80 characters' }
        seo_title = @{ type = 'string'; description = '40-60 characters' }
        seo_description = @{ type = 'string'; description = '120-155 characters' }
        seo_keywords = @{ type = 'string'; description = 'comma-separated, at least 3 keywords' }
        content_block_1 = @{ type = 'string'; description = 'Opening HTML section answering the question directly. Use <h2> and <p> tags. 2-4 paragraphs.' }
        content_block_2 = @{ type = 'string'; description = 'Second HTML section with practical detail/comparison. Use <h2> and <p> tags. 2-4 paragraphs.' }
        content_block_3 = @{ type = 'string'; description = 'Closing HTML section with Wild Papagayo local-expert takeaway. Use <h2> and <p> tags. 1-3 paragraphs.' }
        faq_items = @{
            type = 'array'
            items = @{ type = 'object'; properties = @{ q = @{type='string'}; a = @{type='string'} }; required = @('q','a'); additionalProperties = $false }
        }
        travel_tip = @{ type = 'string'; description = 'One specific, practical local tip, 1 sentence' }
        quick_facts = @{
            type = 'array'
            description = '3-5 short, scannable bullet-point facts pulled from the article body -- not new information, just the most useful takeaways restated briefly.'
            items = @{ type = 'string' }
        }
    }
    required = @('title','excerpt','seo_title','seo_description','seo_keywords','content_block_1','content_block_2','content_block_3','faq_items','travel_tip','quick_facts')
    additionalProperties = $false
}

$contextLines = @()
if ($destNames.Count -gt 0) { $contextLines += "Relevant destinations: $($destNames -join ', ')" }
if ($tourNames.Count -gt 0) { $contextLines += "Relevant Wild Papagayo tours: $($tourNames -join ', ')" }
if ($hotelNames.Count -gt 0) { $contextLines += "Relevant hotels: $($hotelNames -join ', ')" }
if ($q.season_ids) { $contextLines += "Season context: $($q.season_ids -join ', ')" }
if ($q.traveler_profile_ids) { $contextLines += "Traveler profile: $($q.traveler_profile_ids -join ', ')" }

$userPrompt = Repair-Utf8String @"
Write a short travel-guide article for Wild Papagayo (a private tour and transfer company in Guanacaste, Costa Rica) answering this real traveler question:

"$($q.question)"

Suggested angle: $($q.working_title)
Content type: $($q.content_type)
Business goal: $($q.business_goal)
Editorial note: $($q.notes)

$($contextLines -join "`n")

Write in a helpful, locally-informed, non-salesy tone -- like a knowledgeable local friend, not marketing copy. Give a real, balanced, useful answer to the actual question first; only mention Wild Papagayo's own tours/transfers where it's genuinely relevant to the answer, not as a hard sell. Do not invent specific prices, schedules, or availability. HTML content fields should use only <h2>, <p>, <ul>, <li> tags -- no inline styles, no <html>/<body> wrapper.
"@

$requestBody = [ordered]@{
    model = 'claude-opus-4-8'
    max_tokens = 4096
    messages = @(@{ role = 'user'; content = $userPrompt })
    output_config = [ordered]@{ format = [ordered]@{ type = 'json_schema'; schema = $schema } }
} | ConvertTo-Json -Depth 20
$requestBytes = [System.Text.Encoding]::UTF8.GetBytes($requestBody)

$apiHeaders = @{ 'x-api-key' = $apiKey; 'anthropic-version' = '2023-06-01' }

Write-Host "Asking Claude to write: $($q.working_title)" -ForegroundColor Cyan
try {
    $webResponse = Invoke-WebRequest -Uri 'https://api.anthropic.com/v1/messages' -Method Post -Headers $apiHeaders -Body $requestBytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 120 -UseBasicParsing
    $responseText = [System.Text.Encoding]::UTF8.GetString($webResponse.RawContentStream.ToArray())
    $result = $responseText | ConvertFrom-Json
} catch {
    $resp = $_.Exception.Response
    if ($resp) {
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        throw "Claude API error: $($reader.ReadToEnd())"
    }
    throw
}
$textBlock = $result.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1
if (-not $textBlock) { throw "No text content in Claude response: $($result | ConvertTo-Json -Depth 10 -Compress)" }
$written = $textBlock.text | ConvertFrom-Json

# --- 4. Build the blog-data.json article record ---
function New-Slug {
    param([string]$Text)
    # Accented Latin letters (Rio Celeste, articles about penones, etc.) must be
    # transliterated to their base ASCII letter BEFORE stripping non-alphanumeric
    # characters -- otherwise "Rio" becomes "r" + "-" + "o" ("r-o"), producing a
    # mangled, duplicate-prone slug instead of the intended "rio".
    $map = @{ 'á'='a';'é'='e';'í'='i';'ó'='o';'ú'='u';'ñ'='n';'ü'='u' }
    $normalized = $Text.ToLowerInvariant()
    foreach ($k in $map.Keys) { $normalized = $normalized.Replace($k, $map[$k]) }
    $slug = $normalized -replace "[^a-z0-9]+", '-'
    return $slug.Trim('-')
}
$slug = New-Slug $written.title
$suffix = 2
while ($existingSlugs -contains $slug) { $slug = (New-Slug $written.title) + "-$suffix"; $suffix++ }

$faqHtml = "<h2>Frequently Asked Questions</h2>" + (($written.faq_items | ForEach-Object { "<h3>$($_.q)</h3><p>$($_.a)</p>" }) -join "")

$nextId = 1
if ($articles.Count -gt 0) { $nextId = ([int]($articles | ForEach-Object { [int]$_.id } | Measure-Object -Maximum).Maximum) + 1 }

$newArticle = [ordered]@{
    id = $nextId
    slug = $slug
    category = $q.content_type -replace '-', ' '
    date = (Get-Date).ToString('MMMM d, yyyy', [System.Globalization.CultureInfo]::GetCultureInfo('en-US'))
    readTime = [string][Math]::Max(3, [Math]::Round(($written.content_block_1.Length + $written.content_block_2.Length + $written.content_block_3.Length) / 1200))
    iso_date = (Get-Date).ToString('yyyy-MM-ddT00:00:00Z')
    title = $written.title
    excerpt = $written.excerpt
    seo_title_pro = $written.seo_title
    seo_description = $written.seo_description
    seo_keywords = $written.seo_keywords
    author_name = 'Wild Papagayo Local Team'
    author_badge = 'Local Experts'
    image_top = 'images/luxury-costa-rica-tours-hero.webp'
    image_top_alt = $written.title
    content_block_1 = $written.content_block_1
    image_middle = ''
    image_middle_alt = ''
    content_block_2 = $written.content_block_2
    content_block_faq = $faqHtml
    cta_url = 'https://wa.me/50688566325?text=' + [Uri]::EscapeDataString("Hello Wild Papagayo! I read `"$($written.title)`" and would like help planning my trip.")
    cta_text = 'Plan This With a Local Expert'
    image_bottom = ''
    image_bottom_alt = ''
    content_block_3 = $written.content_block_3
    destination_ids = @($q.destination_ids)
    tour_ids = @($q.tour_ids)
    hotel_ids = @($q.hotel_ids)
    activity_ids = @($q.activity_ids)
    season_ids = @($q.season_ids)
    traveler_profile_ids = @($q.traveler_profile_ids)
    transportation_ids = @($q.transportation_ids)
    related_tags = @($q.activity_ids) + @($q.season_ids)
    destinations = @($q.destination_ids)
    travel_tip = $written.travel_tip
    quick_facts = @($written.quick_facts | ForEach-Object { [string]$_ })
    internal_links = if ($transferArticle) { @([ordered]@{ text = 'Airport transfer guide'; url = "../blog/$transferArticle.html" }) } else { @() }
}

$updatedArticles = @($articles) + [pscustomobject]$newArticle
$json = $updatedArticles | ConvertTo-Json -Depth 15
[System.IO.File]::WriteAllText($blogPath, $json, [System.Text.UTF8Encoding]::new($false))

# --- 5. Mark the question as published ---
foreach ($item in $questions) {
    if ($item.id -eq $QuestionId) {
        $item.status = 'published'
        $item.article_slug = $slug
    }
}
[System.IO.File]::WriteAllText($questionsPath, ($questions | ConvertTo-Json -Depth 15), [System.Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host "Article written and added to blog-data.json." -ForegroundColor Green
Write-Host "  slug: $slug"
Write-Host "  Run .\blog-generator.ps1 to publish the HTML page."
[pscustomobject]@{ slug = $slug; question_id = $QuestionId } | ConvertTo-Json -Compress

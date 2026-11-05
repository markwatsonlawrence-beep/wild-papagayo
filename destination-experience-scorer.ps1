# ============================================================
# Wild Papagayo - Destination Experience Scorer v1.0
# Asks Claude to read each destination's REAL, already-written
# editorial text (description, why_visit, highlights,
# considerations, best_for) and score it 1-5 across 8 travel
# categories, with a one-sentence reason grounded in that text.
# Writes the result as "experience_scores" on the destination
# record. Human review recommended before treating as final --
# these are Claude's editorial judgment, not customer reviews.
# Usage: .\destination-experience-scorer.ps1 [-DestinationId "papagayo"]
# Requires ANTHROPIC_API_KEY in wild-papagayo\.env
# ============================================================

[CmdletBinding()]
param(
    [string]$DestinationId
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

$categories = @('adventure', 'families', 'private', 'nightlife', 'restaurants', 'beach', 'wildlife', 'relaxation')

$schema = [ordered]@{
    type = 'object'
    properties = [ordered]@{}
    required = @()
    additionalProperties = $false
}
foreach ($cat in $categories) {
    $schema.properties[$cat] = [ordered]@{
        type = 'object'
        properties = [ordered]@{
            score = @{ type = 'integer'; description = '1-5, grounded strictly in the provided text. If the text says nothing relevant to this category, score conservatively (2) rather than guessing high.' }
            reason = @{ type = 'string'; description = 'One short sentence citing something specific from the provided text.' }
        }
        required = @('score', 'reason')
        additionalProperties = $false
    }
    $schema.required += $cat
}
$schema.properties['difficulty'] = [ordered]@{
    type = 'object'
    properties = [ordered]@{
        level = @{ type = 'string'; enum = @('Easy', 'Medium', 'Advanced'); description = 'How straightforward this destination is for a first-time visitor, based on road conditions, transfer time, and logistics mentioned in the text.' }
        reason = @{ type = 'string'; description = 'One short sentence citing something specific from the provided text (road type, transfer time, terrain, etc).' }
    }
    required = @('level', 'reason')
    additionalProperties = $false
}
$schema.required += 'difficulty'

$destinationsDir = Join-Path $root 'knowledge\destinations'
$files = if ($DestinationId) {
    @(Join-Path $destinationsDir "$DestinationId.json")
} else {
    Get-ChildItem $destinationsDir -Filter '*.json' -File | Select-Object -ExpandProperty FullName
}

foreach ($file in $files) {
    if (-not (Test-Path $file)) { Write-Host "Skip (not found): $file" -ForegroundColor Yellow; continue }
    $d = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    Write-Host "Scoring: $($d.name)..." -ForegroundColor Cyan

    $restaurantList = @($d.restaurants) | ForEach-Object { "$($_.name)$(if ($_.types) { " ($((@($_.types)) -join ', '))" })$(if ($_.rating) { " -- $($_.rating)/5" })" }
    $restaurantContext = if ($restaurantList.Count -gt 0) { "Real, currently-open restaurants and bars near this destination (sourced live from Google): $($restaurantList -join '; ')" } else { "No restaurant/bar data on file for this destination." }

    $context = @"
Destination: $($d.name)
Description: $($d.description)
Why visit: $((@($d.why_visit)) -join ' ')
Highlights: $((@($d.highlights)) -join '; ')
Considerations: $((@($d.considerations)) -join '; ')
Best for (existing tags): $((@($d.best_for)) -join ', ')
Transfer time from nearest airport: $($d.transfer_time)
$restaurantContext
"@

    $userPrompt = @"
$context

Score this Costa Rica destination 1-5 on each of these 8 travel categories: adventure, families, private, nightlife, restaurants, beach, wildlife, relaxation. Base every score strictly on the text above. For "restaurants" and "nightlife" specifically, use the real restaurant/bar list provided (not just the editorial description) -- a long list of real, highly-rated restaurants and bars means dining is genuinely well served even if the description text doesn't dwell on it, and any bars in that list count toward nightlife. If a category has no supporting evidence anywhere in the context, score it conservatively rather than assuming.

Also assess travel difficulty for a first-time visitor (Easy/Medium/Advanced) based on transfer time, terrain and logistics mentioned in the text.
"@

    $requestBody = [ordered]@{
        model = 'claude-opus-4-8'
        max_tokens = 1024
        messages = @(@{ role = 'user'; content = $userPrompt })
        output_config = [ordered]@{ format = [ordered]@{ type = 'json_schema'; schema = $schema } }
    } | ConvertTo-Json -Depth 20
    $requestBytes = [System.Text.Encoding]::UTF8.GetBytes($requestBody)

    try {
        $webResponse = Invoke-WebRequest -Uri 'https://api.anthropic.com/v1/messages' -Method Post -Headers @{ 'x-api-key' = $apiKey; 'anthropic-version' = '2023-06-01' } -Body $requestBytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 90 -UseBasicParsing
        $responseText = [System.Text.Encoding]::UTF8.GetString($webResponse.RawContentStream.ToArray())
        $result = $responseText | ConvertFrom-Json
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            throw "Claude API error for $($d.name): $($reader.ReadToEnd())"
        }
        throw
    }
    $textBlock = $result.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1
    if (-not $textBlock) { Write-Host "  No response for $($d.name), skipping." -ForegroundColor Red; continue }
    $scores = $textBlock.text | ConvertFrom-Json

    $d | Add-Member -NotePropertyName 'experience_scores' -NotePropertyValue $scores -Force
    $json = $d | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($file, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Saved experience_scores for $($d.name)" -ForegroundColor Green
}
Write-Host ''
Write-Host 'Done. Review scores in the CMS before treating them as final.' -ForegroundColor DarkGray

# ============================================================
# Wild Papagayo - Hotel Experience Scorer v1.0
# Fills the "experience_scores" field that has existed on every
# hotel record since creation but has never been computed --
# hotel-create.ps1 scaffolds it at a flat default (score=3 for
# all 7 categories), which is why hotel-generator.ps1 detects
# and HIDES the ratings display rather than show fake uniform
# stars. This script asks Claude to read each hotel's own real,
# already-written editorial text and assign differentiated
# scores grounded in that text. Human review recommended before
# treating as final.
# Usage: .\hotel-experience-scorer.ps1 [-HotelId "hotel-belmar"]
# Requires ANTHROPIC_API_KEY in wild-papagayo\.env
# ============================================================

[CmdletBinding()]
param(
    [string]$HotelId
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

# Same category keys hotel-create.ps1 already scaffolds -- keeps
# Convert-MasterToLegacyHotel and hotel-generator.ps1 compatible.
$categories = @('luxury', 'families', 'couples', 'wellness', 'adventure_access', 'walkability', 'nightlife')

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
            score = @{ type = 'integer'; description = '1-5, grounded strictly in the provided text. If the text says nothing relevant, score conservatively (2-3) rather than guessing high.' }
            reason = @{ type = 'string'; description = 'One short sentence citing something specific from the provided text.' }
        }
        required = @('score', 'reason')
        additionalProperties = $false
    }
    $schema.required += $cat
}

$hotelsDir = Join-Path $root 'knowledge\master\hotels'
$files = if ($HotelId) {
    @(Join-Path $hotelsDir "$HotelId.json")
} else {
    Get-ChildItem $hotelsDir -Filter '*.json' -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' } | Select-Object -ExpandProperty FullName
}

foreach ($file in $files) {
    if (-not (Test-Path $file)) { Write-Host "Skip (not found): $file" -ForegroundColor Yellow; continue }
    $h = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $name = if ($h.identity.display_name) { [string]$h.identity.display_name } else { [string]$h.identity.official_name }
    Write-Host "Scoring: $name..." -ForegroundColor Cyan

    $travelerReasons = @($h.traveler_profile_reasons) | ForEach-Object { "$($_.profile): $($_.reason)" }
    $context = @"
Hotel: $name
Category: $($h.identity.category)
Luxury level: $($h.identity.luxury_level)
Description: $($h.editorial.description)
Local take: $($h.wild_insights.local_take)
Amenities: $((@($h.amenities)) -join '; ')
Traveler fit notes: $($travelerReasons -join '; ')
"@

    $userPrompt = @"
$context

Score this Costa Rica hotel 1-5 on each of these 7 categories: luxury, families, couples, wellness, adventure_access (how easily guests can access adventure tours from here), walkability (walkable to a beach/town center), nightlife. Base every score strictly on the text above -- if the text doesn't support a category, score it conservatively rather than assuming.
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
            throw "Claude API error for $name`: $($reader.ReadToEnd())"
        }
        throw
    }
    $textBlock = $result.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1
    if (-not $textBlock) { Write-Host "  No response for $name, skipping." -ForegroundColor Red; continue }
    $scores = $textBlock.text | ConvertFrom-Json

    $h.experience_scores = $scores
    $json = $h | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($file, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Saved experience_scores for $name" -ForegroundColor Green
}
Write-Host ''
Write-Host 'Done. Review scores in the CMS before treating them as final.' -ForegroundColor DarkGray

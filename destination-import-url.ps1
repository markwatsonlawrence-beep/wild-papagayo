# ============================================================
# Wild Papagayo - Destination Import from URL v1.0
# Same pattern as hotel-import-url.ps1: fetches a real source page
# (tourism board, established travel guide, etc.), asks Claude to
# extract description/why_visit/highlights/considerations/FAQ
# grounded strictly in that page's text, and creates/upgrades the
# per-destination file that destination-generator.ps1 reads from
# (knowledge/destinations/<id>.json). Never invents facts the
# source page doesn't support.
# Usage: .\destination-import-url.ps1 -DestinationId "tamarindo" -Url "https://..."
#   New destination  -> created as status "draft".
#   Existing record  -> ABORTS (non-zero exit), file untouched, unless -Update is given.
#   -Update          -> backup to knowledge\backups\destinations\, then refreshes ONLY the ten
#                       import-owned text fields (description, hero_description, province,
#                       transfer_time, best_season, why_visit, highlights, considerations,
#                       best_for, faq) + verification.source/note. Everything else (status,
#                       hero_image, scores, restaurants, gallery, testimonials, nearby,
#                       relationships, ...) is preserved. Published/disabled records also
#                       need -AllowNonDraft; their status is never changed.
# Requires ANTHROPIC_API_KEY in wild-papagayo\.env
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DestinationId,
    [Parameter(Mandatory=$true)]
    [string]$Url,
    # Explicit refresh of an EXISTING destination (default: abort if it exists).
    [switch]$Update,
    # Additionally required to update an existing published/disabled destination.
    [switch]$AllowNonDraft
)

$ErrorActionPreference = 'Stop'
# Output gets captured by the parent process via `2>&1 | Out-String`; force
# UTF-8 console output or accented characters get mis-encoded in transit.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = $PSScriptRoot

# --- 0. Mode gate: runs BEFORE any network / AI call -----------------------
#  CREATE : target file does not exist -> normal import, record created as "draft".
#  UPDATE : target exists AND -Update given -> backup + narrow merge (see step 4).
#           Published/disabled (or status-less) records also need -AllowNonDraft.
#  Anything else on an existing file aborts (non-zero exit) without touching it.
Add-Type -AssemblyName System.Web.Extensions
$jsonSer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$jsonSer.MaxJsonLength = [int]::MaxValue
$jsonSer.RecursionLimit = 200
$outPath = Join-Path $root "knowledge\destinations\$DestinationId.json"
$isUpdate = $false
$existingBytes = $null
if (Test-Path -LiteralPath $outPath) {
    if (-not $Update) {
        throw "Destination '$DestinationId' already exists ($outPath). Nothing was changed. Re-run with -Update to refresh only its imported text fields (a timestamped backup is created first)."
    }
    $existingBytes = [System.IO.File]::ReadAllBytes($outPath)
    try {
        $existingProbe = $jsonSer.DeserializeObject([System.Text.Encoding]::UTF8.GetString($existingBytes).TrimStart([char]0xFEFF))
    } catch {
        throw "Existing record '$DestinationId' could not be parsed as JSON; refusing to update it. Nothing was changed."
    }
    $existingStatus = if ($existingProbe -is [System.Collections.Generic.IDictionary[string,object]] -and $existingProbe.ContainsKey('status')) { [string]$existingProbe['status'] } else { '' }
    if ($existingStatus -ne 'draft' -and -not $AllowNonDraft) {
        throw "Destination '$DestinationId' has status '$existingStatus' (not 'draft'). -Update alone is not enough; add -AllowNonDraft to update a published/disabled destination. Nothing was changed."
    }
    $isUpdate = $true
} elseif ($Update) {
    Write-Host "Note: -Update was given but '$DestinationId' does not exist yet; creating it as a new draft." -ForegroundColor DarkYellow
}

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

# --- 1. Confirm the destination stub exists in the master list ----------
$masterListPath = Join-Path $root 'knowledge\destinations.json'
$masterList = [System.IO.File]::ReadAllText($masterListPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$stub = $masterList | Where-Object { $_.id -eq $DestinationId } | Select-Object -First 1
if (-not $stub) { throw "'$DestinationId' not found in knowledge\destinations.json. Add the stub entry there first." }

# --- 2. Fetch the page ---------------------------------------------------
Write-Host ''
Write-Host "Fetching: $Url" -ForegroundColor Cyan
$headers = @{ 'User-Agent' = 'Mozilla/5.0 (compatible; WildPapagayoImportBot/1.0; +https://wildpapagayo.com)' }
$response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers $headers -TimeoutSec 45 -MaximumRedirection 8
$rawBytes = $response.RawContentStream.ToArray()
$html = [System.Text.Encoding]::UTF8.GetString($rawBytes)

function Get-PlainText {
    param([string]$Html, [int]$MaxChars = 14000)
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
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $utf8 = New-Object System.Text.UTF8Encoding($false, $false)
    return $utf8.GetString($utf8.GetBytes($Text))
}
$plainText = Get-PlainText $html
Write-Host "Page text: $($plainText.Length) chars" -ForegroundColor DarkGray

# --- 3. Ask Claude to extract, grounded strictly in the fetched text -----
Write-Host "Asking Claude to read the page and extract destination details..." -ForegroundColor Cyan

$schema = [ordered]@{
    type = 'object'
    properties = [ordered]@{
        description = @{ type = 'string'; description = '2-3 sentence editorial description for a travel guide, 80-400 characters' }
        hero_description = @{ type = 'string'; description = 'One short sentence for a hero banner' }
        province = @{ type = 'string'; description = 'Costa Rican province, e.g. Guanacaste, Puntarenas' }
        transfer_time = @{ type = 'string'; description = 'Approximate transfer time from the nearest major airport, as a range, e.g. "45-60 minutes". Only state this if the source text supports it or it can be reasonably estimated from stated distance; otherwise return empty string.' }
        best_season = @{ type = 'string'; description = 'Best months/season to visit, e.g. "December-April", only if the source supports it, else empty string' }
        why_visit = @{ type = 'array'; items = @{ type = 'string' }; description = '1-2 paragraphs on why to visit, grounded in the text' }
        highlights = @{ type = 'array'; items = @{ type = 'string' }; description = '3-6 short highlight bullets grounded in the text' }
        considerations = @{ type = 'array'; items = @{ type = 'string' }; description = '1-3 honest practical considerations (crowds, price, access) grounded in the text. Empty array if the text does not support any.' }
        best_for = @{ type = 'array'; items = @{ type = 'string' }; description = '2-4 short traveler-type tags, e.g. "Families", "Surfers", "Couples"' }
        faq = @{
            type = 'array'
            description = 'Exactly 4 items'
            items = @{
                type = 'object'
                properties = @{ q = @{type='string'}; a = @{type='string'} }
                required = @('q','a')
                additionalProperties = $false
            }
        }
    }
    required = @('description','hero_description','province','transfer_time','best_season','why_visit','highlights','considerations','best_for','faq')
    additionalProperties = $false
}

$userPrompt = @"
Destination: $($stub.name)
Source URL: $Url

Extracted page text:
---
$plainText
---

Read the page text above and extract real, grounded details about this Costa Rica destination for a private-tour company's travel guide entry. Do not invent facts the page doesn't support -- if transfer_time or best_season aren't stated or reasonably inferable, return an empty string for that field rather than guessing. The "faq" array must contain exactly 4 items grounded in the text.
"@

$requestBody = [ordered]@{
    model = 'claude-opus-4-8'
    max_tokens = 2048
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
        throw "Claude API error: $($reader.ReadToEnd())"
    }
    throw
}
$textBlock = $result.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1
if (-not $textBlock) { throw "No text content in Claude response." }
$extracted = $textBlock.text | ConvertFrom-Json

# --- 4. Resolve airport display + write the per-destination file ---------
$airportsPath = Join-Path $root 'knowledge\airports.json'
$airports = [System.IO.File]::ReadAllText($airportsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$airportId = @($stub.airport_ids) | Select-Object -First 1
$airport = $airports | Where-Object { $_.id -eq $airportId } | Select-Object -First 1
$airportLabel = if ($airport) { "$($airport.name) ($($airport.iata))" } else { '' }

$toursDir = Join-Path $root 'knowledge\tours'
$featuredTours = @(Get-ChildItem $toursDir -Filter '*.json' -File | ForEach-Object {
    $t = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if (@($t.destination_ids) -contains $DestinationId) { $t.id }
} | Select-Object -First 3)

$destinationRecord = [ordered]@{
    id = $DestinationId
    # New destinations are ALWAYS created as drafts. Promote explicitly by setting
    # "status": "published" once the record and page are reviewed and ready.
    status = 'draft'
    name = [string]$stub.name
    hero_image = 'images/luxury-costa-rica-tours-hero.webp'
    hero_description = [string]$extracted.hero_description
    description = [string]$extracted.description
    airport = $airportLabel
    transfer_time = [string]$extracted.transfer_time
    best_season = [string]$extracted.best_season
    best_for = @($extracted.best_for)
    nearby = @($stub.nearby_ids)
    featured_tours = $featuredTours
    province = [string]$extracted.province
    why_visit = @($extracted.why_visit)
    highlights = @($extracted.highlights)
    considerations = @($extracted.considerations)
    faq = @($extracted.faq | ForEach-Object { [pscustomobject]@{ q = [string]$_.q; a = [string]$_.a } })
    airport_id = $airportId
    relationships = [ordered]@{
        tours = $featuredTours
        destinations = @($stub.nearby_ids)
        nearby_hotels = @()
        blogs = @()
        last_discovered = (Get-Date).ToString('yyyy-MM-dd')
    }
    verification = [ordered]@{
        status = 'unverified'
        source = $Url
        note = 'Imported from source URL and summarized by Claude. Facts should be human-reviewed before publication.'
    }
}

function Format-JsonPretty([string]$Json) {
    # String-aware pretty printer (2-space indent, CRLF) for the compact serializer output.
    $sb = New-Object System.Text.StringBuilder
    $level = 0; $inStr = $false; $esc = $false
    for ($i = 0; $i -lt $Json.Length; $i++) {
        $c = $Json[$i]
        if ($inStr) {
            [void]$sb.Append($c)
            if ($esc) { $esc = $false } elseif ($c -eq '\') { $esc = $true } elseif ($c -eq '"') { $inStr = $false }
            continue
        }
        if ($c -eq '"') { $inStr = $true; [void]$sb.Append($c) }
        elseif ($c -eq '{' -or $c -eq '[') {
            $next = if ($i + 1 -lt $Json.Length) { $Json[$i + 1] } else { '' }
            if (($c -eq '{' -and $next -eq '}') -or ($c -eq '[' -and $next -eq ']')) { [void]$sb.Append($c).Append($next); $i++ }
            else { $level++; [void]$sb.Append($c).Append("`r`n").Append(' ' * ($level * 2)) }
        }
        elseif ($c -eq '}' -or $c -eq ']') { $level--; [void]$sb.Append("`r`n").Append(' ' * ($level * 2)).Append($c) }
        elseif ($c -eq ',') { [void]$sb.Append(",`r`n").Append(' ' * ($level * 2)) }
        elseif ($c -eq ':') { [void]$sb.Append(': ') }
        else { [void]$sb.Append($c) }
    }
    return $sb.ToString()
}

if (-not $isUpdate) {
    # CREATE: unchanged behaviour (the file does not exist; record is a new draft).
    $json = $destinationRecord | ConvertTo-Json -Depth 15
    [System.IO.File]::WriteAllText($outPath, $json, [System.Text.UTF8Encoding]::new($false))
} else {
    # UPDATE: back up first, merge ONLY the import-owned text fields, validate, write atomically.
    $existingText = [System.Text.Encoding]::UTF8.GetString($existingBytes).TrimStart([char]0xFEFF)
    $orig = $jsonSer.DeserializeObject($existingText)          # working copy (dictionary; key order preserved)
    $pristine = $jsonSer.DeserializeObject($existingText)      # untouched copy for the safety comparison

    # 1) Backup (complete original bytes, never overwrites an existing backup). Failure aborts the update.
    $backupDir = Join-Path $root 'knowledge\backups\destinations'
    try {
        [void][System.IO.Directory]::CreateDirectory($backupDir)
        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss'); $n = 0
        do {
            $suffix = if ($n -eq 0) { '' } else { "-$n" }
            $backupPath = Join-Path $backupDir "$DestinationId-$stamp$suffix.json"
            $n++
        } while (Test-Path -LiteralPath $backupPath)
        [System.IO.File]::Copy($outPath, $backupPath, $false)
        $a = [System.IO.File]::ReadAllBytes($backupPath)
        if ($a.Length -ne $existingBytes.Length -or [System.BitConverter]::ToString($a) -ne [System.BitConverter]::ToString($existingBytes)) { throw 'backup content mismatch' }
    } catch {
        throw "Backup failed ($($_.Exception.Message)). Update aborted; '$DestinationId' was not modified."
    }

    # 2) Merge: exactly these ten import-owned text fields (+ verification.source/note). Nothing else.
    $refreshable = @('description','hero_description','province','transfer_time','best_season','why_visit','highlights','considerations','best_for','faq')
    $refreshed = New-Object System.Collections.Generic.List[string]
    $skipped = New-Object System.Collections.Generic.List[string]
    foreach ($f in $refreshable) {
        $new = $destinationRecord[$f]
        $value = $null
        if ($f -eq 'faq') {
            $items = New-Object System.Collections.ArrayList
            foreach ($item in @($new)) {
                if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item.q) -and -not [string]::IsNullOrWhiteSpace([string]$item.a)) {
                    $d = New-Object 'System.Collections.Generic.Dictionary[string,object]'
                    $d.set_Item('q', [string]$item.q); $d.set_Item('a', [string]$item.a); [void]$items.Add($d)
                }
            }
            if ($items.Count -gt 0) { $value = $items }
        } elseif ($new -is [System.Array]) {
            $items = New-Object System.Collections.ArrayList
            foreach ($item in $new) { if (-not [string]::IsNullOrWhiteSpace([string]$item)) { [void]$items.Add([string]$item) } }
            if ($items.Count -gt 0) { $value = $items }
        } else {
            if (-not [string]::IsNullOrWhiteSpace([string]$new)) { $value = [string]$new }
        }
        if ($null -eq $value) { $skipped.Add($f); continue }   # empty/invalid extraction never blanks a populated field
        $orig.set_Item($f, $value)   # set_Item (not the indexer) so PowerShell does not wrap the value in a PSObject
        $refreshed.Add($f)
    }
    $ver = if ($orig.ContainsKey('verification') -and $orig['verification'] -is [System.Collections.IDictionary]) { $orig['verification'] } else { $null }
    if ($null -eq $ver) { $ver = New-Object 'System.Collections.Generic.Dictionary[string,object]'; $ver.set_Item('status', 'unverified'); $orig.set_Item('verification', $ver) }
    $ver.set_Item('source', $Url)
    $ver.set_Item('note', 'Text refreshed from source URL via -Update and summarized by Claude. Facts should be human-reviewed before publication.')

    # 3) Self-check: every key outside the approved set must be identical to the original; no key removed or reordered.
    $allowed = $refreshable + @('verification')
    $origKeys = @($pristine.Keys); $newKeys = @($orig.Keys)
    for ($k = 0; $k -lt $origKeys.Count; $k++) {
        if ($newKeys[$k] -ne $origKeys[$k]) { throw "Safety check failed: key order/set changed at '$($origKeys[$k])'. Nothing was modified." }
    }
    foreach ($k in $origKeys) {
        if ($allowed -contains $k) { continue }
        if ($jsonSer.Serialize($orig[$k]) -ne $jsonSer.Serialize($pristine[$k])) { throw "Safety check failed: protected field '$k' would change. Nothing was modified." }
    }
    if ($pristine.ContainsKey('verification') -and $pristine['verification'] -is [System.Collections.Generic.IDictionary[string,object]]) {
        foreach ($k in @($pristine['verification'].Keys)) {
            if ($k -in @('source','note')) { continue }
            if ($jsonSer.Serialize($orig['verification'][$k]) -ne $jsonSer.Serialize($pristine['verification'][$k])) { throw "Safety check failed: verification.$k would change. Nothing was modified." }
        }
    }
    $statusBefore = if ($pristine.ContainsKey('status')) { [string]$pristine['status'] } else { '<missing>' }
    $statusAfter = if ($orig.ContainsKey('status')) { [string]$orig['status'] } else { '<missing>' }
    if ($statusAfter -ne $statusBefore) { throw 'Safety check failed: status would change. Nothing was modified.' }

    # 4) Validate the candidate, write to a temp file, then atomically replace the original.
    $candidate = Format-JsonPretty ($jsonSer.Serialize($orig))
    $roundTrip = $jsonSer.DeserializeObject($candidate)
    if ($jsonSer.Serialize($roundTrip) -ne $jsonSer.Serialize($orig)) { throw 'Candidate JSON failed validation. Nothing was modified.' }
    $tmp = "$outPath.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        [System.IO.File]::WriteAllText($tmp, $candidate, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Replace($tmp, $outPath, [NullString]::Value)   # atomic swap, no .bak file
    } catch {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        throw "Update failed while writing ($($_.Exception.Message)). The original record is unchanged."
    }
    Write-Host "  Updated (status kept as '$statusAfter'). Backup: $backupPath" -ForegroundColor Yellow
    Write-Host "  Refreshed: $($refreshed -join ', ')" -ForegroundColor DarkGray
    if ($skipped.Count -gt 0) { Write-Host "  Kept existing (empty/invalid extraction): $($skipped -join ', ')" -ForegroundColor DarkGray }
}

# Automatic photo sourcing via destination-photo-finder.ps1 (Google Places Photos)
# is intentionally disabled here -- this project had a real legal issue from using
# third-party-sourced photos before, and photos had to be removed as a result.
# Hero images must be added manually with owned/licensed/explicitly authorized
# imagery. Run destination-photo-finder.ps1 by hand only if you have confirmed the
# photo source is legally usable.
Write-Host "  Hero image left as generic placeholder -- add a real, licensed photo manually." -ForegroundColor DarkYellow

Write-Host ''
Write-Host "Destination imported: $DestinationId" -ForegroundColor Green
Write-Host "  path: $outPath"
if (-not $isUpdate) { Write-Host '  Created with status "draft" -- it will NOT be generated, listed or linked until you set "status": "published".' -ForegroundColor DarkYellow }
[pscustomobject]@{ id = $DestinationId; path = $outPath } | ConvertTo-Json -Compress

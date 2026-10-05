# ============================================================
# Wild Papagayo - AI Assistant Knowledge Validator v1.0
# Validates functions/assistant-knowledge.json (the file Bubu's
# system prompt is built from) before it's allowed into a deploy.
# Mirrors the pattern already established by content-link-validator.ps1:
# a standalone, independently-runnable check with a clear PASS/FAIL
# exit code, meant to be called from deploy-package.ps1 but usable
# on its own for local testing.
# ============================================================
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$knowledgePath = Join-Path $root "functions\assistant-knowledge.json"

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-ValidationError([string]$msg) { $errors.Add($msg) }
function Add-ValidationWarning([string]$msg) { $warnings.Add($msg) }

# ---- JSON validity / file presence ----
if (-not (Test-Path $knowledgePath)) {
    Write-Host "Knowledge Validation"
    Write-Host ""
    Write-Host "FATAL: $knowledgePath does not exist." -ForegroundColor Red
    Write-Host ""
    Write-Host "RESULT: FAIL" -ForegroundColor Red
    exit 1
}

$rawText = [System.IO.File]::ReadAllText($knowledgePath, [System.Text.Encoding]::UTF8)
if ([string]::IsNullOrWhiteSpace($rawText)) {
    Write-Host "Knowledge Validation"
    Write-Host ""
    Write-Host "FATAL: $knowledgePath is empty." -ForegroundColor Red
    Write-Host ""
    Write-Host "RESULT: FAIL" -ForegroundColor Red
    exit 1
}

try {
    $knowledge = $rawText | ConvertFrom-Json
} catch {
    Write-Host "Knowledge Validation"
    Write-Host ""
    Write-Host "FATAL: $knowledgePath is not valid JSON: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "RESULT: FAIL" -ForegroundColor Red
    exit 1
}

$hotels = @($knowledge.hotels)
$tours = @($knowledge.tours)
$destinations = @($knowledge.destinations)
$articles = @($knowledge.articles)
$transfers = @($knowledge.transfers)

# ---- Category presence (0 in any = error, per explicit instruction) ----
if ($hotels.Count -eq 0) { Add-ValidationError "hotels category is empty (0 entries)" }
if ($tours.Count -eq 0) { Add-ValidationError "tours category is empty (0 entries)" }
if ($destinations.Count -eq 0) { Add-ValidationError "destinations category is empty (0 entries)" }
if ($articles.Count -eq 0) { Add-ValidationError "articles category is empty (0 entries)" }
if ($transfers.Count -eq 0) { Add-ValidationError "transfers category is empty (0 entries)" }

# ---- Required fields: name + slug/URL on every entry ----
function Test-RequiredFields($items, [string]$categoryName, [string]$nameField, [string]$urlField) {
    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        $nameVal = $item.$nameField
        $urlVal = $item.$urlField
        if ([string]::IsNullOrWhiteSpace([string]$nameVal)) { Add-ValidationError "$categoryName[$i] is missing '$nameField'" }
        if ([string]::IsNullOrWhiteSpace([string]$urlVal)) { Add-ValidationError "$categoryName[$i] ('$nameVal') is missing '$urlField'" }
    }
}
Test-RequiredFields $hotels "hotels" "name" "url"
Test-RequiredFields $tours "tours" "name" "url"
Test-RequiredFields $destinations "destinations" "name" "url"
Test-RequiredFields $articles "articles" "title" "url"
Test-RequiredFields $transfers "transfers" "name" "url"

# ---- Duplicate URL detection (across each category, and sitewide) ----
function Get-Duplicates($values) {
    $seen = @{}
    $dupes = New-Object System.Collections.Generic.List[string]
    foreach ($v in $values) {
        if ([string]::IsNullOrWhiteSpace([string]$v)) { continue }
        if ($seen.ContainsKey([string]$v)) { $dupes.Add([string]$v) } else { $seen[[string]$v] = $true }
    }
    return $dupes
}
$allUrls = @($hotels | ForEach-Object { $_.url }) + @($tours | ForEach-Object { $_.url }) + @($destinations | ForEach-Object { $_.url }) + @($articles | ForEach-Object { $_.url }) + @($transfers | ForEach-Object { $_.url })
$dupeUrls = Get-Duplicates $allUrls
foreach ($d in ($dupeUrls | Select-Object -Unique)) { Add-ValidationError "duplicate URL across knowledge categories: $d" }

# ---- Broken-reference check: does the referenced page actually exist on disk? ----
# $root ($PSScriptRoot) IS the site root -- this script lives directly in
# wild-papagayo/, alongside functions/, hotels/, tours/, etc.
$siteRoot = $root
foreach ($category in @(
    @{ Items = $hotels; Name = "hotels" }, @{ Items = $tours; Name = "tours" },
    @{ Items = $destinations; Name = "destinations" }, @{ Items = $articles; Name = "articles" },
    @{ Items = $transfers; Name = "transfers" }
)) {
    foreach ($item in $category.Items) {
        $url = [string]$item.url
        if ([string]::IsNullOrWhiteSpace($url)) { continue }
        $relPath = $url.TrimStart('/')
        $fullPath = Join-Path $siteRoot $relPath
        # Site pages are served at clean (extensionless) URLs via Cloudflare
        # Pages' own .html redirect/rewrite, but the physical file on disk is
        # still saved as <path>.html -- check both so this doesn't flag every
        # legitimately clean-URL page as broken.
        if (-not (Test-Path $fullPath) -and -not (Test-Path "$fullPath.html")) { Add-ValidationError "$($category.Name) entry '$($item.name)$($item.title)' references a page that does not exist on disk: $url" }
    }
}

# ---- Riu-specific required checks (Section 12/Step 4's ongoing guard) ----
$riuGuanacasteHotel = @($hotels | Where-Object { $_.name -eq 'Hotel Riu Guanacaste' })
$riuPalaceHotel = @($hotels | Where-Object { $_.name -eq 'Hotel Riu Palace Costa Rica' })
$riuGuanacasteTransfer = @($transfers | Where-Object { $_.url -eq '/transfers/liberia-airport-to-riu-guanacaste.html' })
$riuPalaceTransfer = @($transfers | Where-Object { $_.url -eq '/transfers/liberia-airport-to-riu-palace-costa-rica.html' })

if ($riuGuanacasteHotel.Count -eq 0) { Add-ValidationError "Hotel Riu Guanacaste is missing from the hotels category" }
if ($riuPalaceHotel.Count -eq 0) { Add-ValidationError "Hotel Riu Palace Costa Rica is missing from the hotels category" }
if ($riuGuanacasteTransfer.Count -eq 0) { Add-ValidationError "Liberia Airport to Riu Guanacaste transfer is missing from the transfers category" }
if ($riuPalaceTransfer.Count -eq 0) { Add-ValidationError "Liberia Airport to Riu Palace Costa Rica transfer is missing from the transfers category" }
if ($riuGuanacasteHotel.Count -gt 0 -and $riuPalaceHotel.Count -gt 0 -and $riuGuanacasteHotel[0].name -eq $riuPalaceHotel[0].name) {
    Add-ValidationError "Riu Guanacaste and Riu Palace Costa Rica appear to be merged into a single hotel entry"
}

# ---- Summary ----
Write-Host "Knowledge Validation"
Write-Host ""
Write-Host "Hotels: $($hotels.Count)"
Write-Host "Tours: $($tours.Count)"
Write-Host "Destinations: $($destinations.Count)"
Write-Host "Articles: $($articles.Count)"
Write-Host "Transfers: $($transfers.Count)"
Write-Host ""
Write-Host "Errors: $($errors.Count)"
Write-Host "Warnings: $($warnings.Count)"
Write-Host ""
foreach ($e in $errors) { Write-Host "  ERROR: $e" -ForegroundColor Red }
foreach ($w in $warnings) { Write-Host "  WARNING: $w" -ForegroundColor Yellow }
Write-Host ""

if ($errors.Count -gt 0) {
    Write-Host "RESULT: FAIL" -ForegroundColor Red
    exit 1
} else {
    Write-Host "RESULT: PASS" -ForegroundColor Green
    exit 0
}

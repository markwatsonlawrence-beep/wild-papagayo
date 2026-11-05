# ============================================================
# Wild Papagayo - Destination Health Report v1.0
# Scores each destination on real, countable knowledge-graph
# coverage (articles, hotels, tours, FAQ, highlights, images) --
# no hand-written opinions -- and flags what's genuinely missing
# so editorial effort goes where it has the most impact.
# ============================================================
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$destinationsDir = Join-Path $root "knowledge\destinations"
$reportsDir = Join-Path $root "reports"
New-Item -ItemType Directory -Force $reportsDir | Out-Null

function Read-Utf8Json([string]$path) { return ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }

$blogPath = Join-Path $root 'blog-data.json'
$articles = if (Test-Path $blogPath) { Read-Utf8Json $blogPath } else { @() }
$articles = @($articles)

$hotelsDir = Join-Path $root 'knowledge\master\hotels'
$hotels = @()
if (Test-Path $hotelsDir) {
    $hotels = Get-ChildItem $hotelsDir -Filter '*.json' -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' } | ForEach-Object {
        $h = Read-Utf8Json $_.FullName
        [pscustomobject]@{ destination_id = [string]$h.location.destination_id }
    }
}

$toursDir = Join-Path $root 'knowledge\tours'
$tours = @()
if (Test-Path $toursDir) {
    $tours = Get-ChildItem $toursDir -Filter '*.json' -File | ForEach-Object {
        $t = Read-Utf8Json $_.FullName
        [pscustomobject]@{ destination_ids = @($t.destination_ids) }
    }
}

$destFiles = Get-ChildItem $destinationsDir -Filter '*.json' -File | Sort-Object Name
$results = New-Object System.Collections.Generic.List[object]

foreach ($file in $destFiles) {
    $d = Read-Utf8Json $file.FullName
    $destId = [string]$d.id

    $articleCount = @($articles | Where-Object { (@($_.destination_ids) + @($_.destinations)) -contains $destId }).Count
    $hotelCount = @($hotels | Where-Object { $_.destination_id -eq $destId }).Count
    $linkedTourCount = @($tours | Where-Object { $_.destination_ids -contains $destId }).Count
    $curatedTourCount = @($d.featured_tours).Count
    $tourCount = [Math]::Max($linkedTourCount, $curatedTourCount)
    $faqCount = @($d.faq).Count
    $highlightCount = @($d.highlights).Count
    $hasImage = -not [string]::IsNullOrWhiteSpace([string]$d.hero_image)

    $score = 0
    if ($articleCount -ge 3) { $score += 25 } elseif ($articleCount -ge 1) { $score += 12 }
    if ($hotelCount -ge 2) { $score += 15 } elseif ($hotelCount -ge 1) { $score += 8 }
    if ($tourCount -ge 3) { $score += 20 } elseif ($tourCount -ge 1) { $score += 10 }
    if ($faqCount -ge 3) { $score += 15 } elseif ($faqCount -ge 1) { $score += 7 }
    if ($highlightCount -ge 3) { $score += 15 }
    if ($hasImage) { $score += 10 }
    $score = [Math]::Min(100, $score)

    $missing = New-Object System.Collections.Generic.List[string]
    if ($articleCount -eq 0) { $missing.Add('Articles') }
    if ($hotelCount -eq 0) { $missing.Add('Hotels') }
    if ($tourCount -eq 0) { $missing.Add('Tours') }
    if ($faqCount -lt 3) { $missing.Add('FAQ (fewer than 3)') }
    if ($highlightCount -eq 0) { $missing.Add('Highlights') }
    if (-not $hasImage) { $missing.Add('Hero image') }

    $results.Add([pscustomobject]@{
        id = $destId
        name = [string]$d.name
        score = $score
        articles = $articleCount
        hotels = $hotelCount
        tours = $tourCount
        faq = $faqCount
        missing = $missing.ToArray()
    })
}

$ranked = @($results | Sort-Object score)

Write-Host ''
Write-Host 'Destination Health Report' -ForegroundColor Cyan
Write-Host '=========================' -ForegroundColor Cyan
foreach ($r in $ranked) {
    $stars = ('*' * [Math]::Round($r.score / 20)).PadRight(5, '-')
    Write-Host ''
    Write-Host "$($r.name)  [$stars]  $($r.score)%" -ForegroundColor $(if ($r.score -ge 80) { 'Green' } elseif ($r.score -ge 50) { 'Yellow' } else { 'Red' })
    Write-Host "  Articles: $($r.articles)  Hotels: $($r.hotels)  Tours: $($r.tours)  FAQ: $($r.faq)"
    if ($r.missing.Count -gt 0) { Write-Host "  Missing: $($r.missing -join ', ')" -ForegroundColor DarkYellow }
}

$outPath = Join-Path $reportsDir 'destination-health.json'
$json = $ranked | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($outPath, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host ''
Write-Host "Report saved: reports\destination-health.json" -ForegroundColor DarkGray

# ============================================================
# Wild Papagayo - Content Link & Image Validator v1.0
# Scans every generated page (blog/, hotels/, destinations/,
# tours/) for:
#   - <img src="..."> pointing at a file that doesn't exist
#   - relative <a href="..."> pointing at a page that doesn't exist
#   - leftover unresolved __TEMPLATE_MARKER__ placeholders
# Writes reports/content-validation-report.txt (human) and
# reports/content-validation-report.json (machine).
# Usage: .\content-link-validator.ps1
# ============================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$reportDir = Join-Path $root 'reports'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$scanFolders = @('blog', 'hotels', 'destinations', 'tours', 'months', 'categories', 'profiles', 'packages', 'private-tours')
$issues = New-Object System.Collections.Generic.List[object]
$pagesScanned = 0
$imagesChecked = 0
$linksChecked = 0

function Add-Issue {
    param([string]$File, [string]$Type, [string]$Target)
    $issues.Add([pscustomobject]@{ file = $File; type = $Type; target = $Target })
}

foreach ($folder in $scanFolders) {
    $folderPath = Join-Path $root $folder
    if (-not (Test-Path $folderPath)) { continue }

    foreach ($page in Get-ChildItem $folderPath -Filter '*.html' -File) {
        $pagesScanned++
        $html = [System.IO.File]::ReadAllText($page.FullName, [System.Text.Encoding]::UTF8)
        $relLabel = "$folder/$($page.Name)"

        # Unresolved template markers left over from a broken generator run
        foreach ($m in [regex]::Matches($html, '__[A-Z_]+__')) {
            Add-Issue -File $relLabel -Type 'unresolved-marker' -Target $m.Value
        }

        # Images
        foreach ($m in [regex]::Matches($html, '<img[^>]+src="([^"]+)"')) {
            $src = $m.Groups[1].Value
            if ($src -match '^(https?:)?//' -or $src -match '^data:') { continue }
            $imagesChecked++
            $resolved = [IO.Path]::GetFullPath((Join-Path $page.DirectoryName $src))
            if (-not (Test-Path $resolved -PathType Leaf)) {
                Add-Issue -File $relLabel -Type 'missing-image' -Target $src
            }
        }

        # Internal links (relative only -- skip external, mailto, tel, whatsapp, anchors)
        foreach ($m in [regex]::Matches($html, '<a[^>]+href="([^"]+)"')) {
            $href = $m.Groups[1].Value
            if ($href -match '^(https?:)?//' -or $href -match '^(mailto|tel):' -or $href -match '^#' -or [string]::IsNullOrWhiteSpace($href)) { continue }
            $linksChecked++
            $hrefPath = ($href -split '#')[0] -split '\?' | Select-Object -First 1
            if ([string]::IsNullOrWhiteSpace($hrefPath)) { continue }
            $resolved = [IO.Path]::GetFullPath((Join-Path $page.DirectoryName $hrefPath))
            # Clean canonical URLs (no .html) are a deliberate site-wide convention
            # (see sitemap.xml/RSS/canonical tags) -- Cloudflare Pages 308-redirects
            # them to the real file, so a link without .html is not broken as long
            # as the underlying .html file actually exists.
            if ($hrefPath.EndsWith('/')) {
                # Directory/root link (e.g. "../") -- valid if it resolves to
                # a real directory that has an index.html.
                if (-not (Test-Path (Join-Path $resolved 'index.html') -PathType Leaf)) {
                    Add-Issue -File $relLabel -Type 'broken-link' -Target $href
                }
            } elseif (-not (Test-Path $resolved -PathType Leaf) -and -not (Test-Path "$resolved.html" -PathType Leaf)) {
                Add-Issue -File $relLabel -Type 'broken-link' -Target $href
            }
        }
    }
}

$byType = $issues | Group-Object type | Sort-Object Count -Descending
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('Wild Papagayo - Content Validation Report')
$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add('')
$lines.Add("Pages scanned:   $pagesScanned")
$lines.Add("Images checked:  $imagesChecked")
$lines.Add("Links checked:   $linksChecked")
$lines.Add("Issues found:    $($issues.Count)")
$lines.Add('')
foreach ($group in $byType) {
    $lines.Add("== $($group.Name) ($($group.Count)) ==")
    foreach ($issue in $group.Group) { $lines.Add("  $($issue.file) -> $($issue.target)") }
    $lines.Add('')
}

$reportPath = Join-Path $reportDir 'content-validation-report.txt'
[System.IO.File]::WriteAllLines($reportPath, $lines, [System.Text.UTF8Encoding]::new($false))

$jsonPath = Join-Path $reportDir 'content-validation-report.json'
[ordered]@{
    generated       = (Get-Date).ToString('s')
    pages_scanned   = $pagesScanned
    images_checked  = $imagesChecked
    links_checked   = $linksChecked
    issue_count     = $issues.Count
    issues          = $issues
} | ConvertTo-Json -Depth 6 | Out-File -FilePath $jsonPath -Encoding utf8

Write-Host ''
if ($issues.Count -eq 0) {
    Write-Host "Content validation passed -- $pagesScanned pages, $imagesChecked images, $linksChecked links, 0 issues." -ForegroundColor Green
} else {
    Write-Host "Content validation found $($issues.Count) issue(s) across $pagesScanned pages." -ForegroundColor Yellow
    foreach ($group in $byType) { Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor Yellow }
}
Write-Host "Report: $reportPath"

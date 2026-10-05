# ============================================================
# Wild Papagayo - sitemap.xml Generator v1.0
# Scans the actual generated site for real .html files and builds
# sitemap.xml from what's really there -- so a new hotel/tour/blog
# article/destination automatically appears in the sitemap the next
# time the site is rebuilt, with no manual step required.
# Run as part of deploy-package.ps1; can also be run standalone.
# ============================================================
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$siteUrl = "https://wildpapagayo.com"
$today = Get-Date -Format "yyyy-MM-dd"

# Real per-file last-modified date, not "today" for every URL -- the
# generators now only rewrite a file when its content actually changed
# (see Write-FileIfChanged in each *-generator.ps1), so a file's mtime on
# disk is a genuine signal of when that specific page last changed. Using
# "today" for all ~150 URLs on every deploy taught Google to distrust our
# lastmod signal entirely, which hurt crawl prioritization.
function Get-FileLastMod {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $today }
    return (Get-Item $Path).LastWriteTime.ToString('yyyy-MM-dd')
}

# Root-level hand-authored/generated pages worth indexing (excludes
# admin/legal-adjacent utility pages that add no SEO value: 404,
# offline, Bookingform is a conversion form not a landing page).
$rootPages = @(
    'index.html','tours.html','transport.html','about.html','contact.html',
    'Blogs.html','guides.html','paquete.html','hotels.html','travel-insurance.html',
    'months.html','tour-finder.html','destination-finder.html',
    'plan-by-traveler-type.html','waterfalls-near-papagayo-guide.html',
    'Terminosycondiciones.html','politicasdeprivacidad.html','politicasdecancelacion.html'
)

# Content directories: folder name -> [changefreq, priority]
$contentDirs = [ordered]@{
    'blog'          = @('monthly', '0.7')
    'tours'         = @('monthly', '0.8')
    'hotels'        = @('monthly', '0.8')
    'destinations'  = @('monthly', '0.8')
    'categories'    = @('weekly',  '0.6')
    'months'        = @('monthly', '0.6')
    'profiles'      = @('monthly', '0.6')
    'packages'      = @('monthly', '0.7')
    'private-tours' = @('monthly', '0.8')
    'transfers'     = @('monthly', '0.8')
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('<?xml version="1.0" encoding="UTF-8"?>')
$lines.Add('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')

foreach ($page in $rootPages) {
    $path = Join-Path $root $page
    if (Test-Path $path) {
        # Cloudflare Pages always 308-redirects *.html to the extensionless
        # path, so the sitemap/canonical must point there directly -- index.html
        # collapses to the bare root.
        $slug = if ($page -eq 'index.html') { '' } else { $page -replace '\.html$', '' }
        $lines.Add("  <url><loc>$siteUrl/$slug</loc><lastmod>$(Get-FileLastMod $path)</lastmod><changefreq>weekly</changefreq><priority>0.9</priority></url>")
    }
}

foreach ($dir in $contentDirs.Keys) {
    $dirPath = Join-Path $root $dir
    if (-not (Test-Path $dirPath)) { continue }
    $freq, $priority = $contentDirs[$dir]
    Get-ChildItem $dirPath -Filter '*.html' -File | Sort-Object Name | ForEach-Object {
        $slug = $_.Name -replace '\.html$', ''
        # Destinations: eligibility comes from the destination RECORD, never from the
        # HTML file merely existing on disk -- a stale page for a draft/unknown
        # destination must not enter the sitemap. Only status "published" is listed.
        if ($dir -eq 'destinations') {
            $destRecord = Join-Path $root "knowledge\destinations\$slug.json"
            if (-not (Test-Path $destRecord)) { return }
            $destStatus = [string]([System.IO.File]::ReadAllText($destRecord, [System.Text.Encoding]::UTF8) | ConvertFrom-Json).status
            if ($destStatus -ne 'published') { return }
        }
        $lines.Add("  <url><loc>$siteUrl/$dir/$slug</loc><lastmod>$($_.LastWriteTime.ToString('yyyy-MM-dd'))</lastmod><changefreq>$freq</changefreq><priority>$priority</priority></url>")
    }
}

$lines.Add('</urlset>')

$outPath = Join-Path $root 'sitemap.xml'
[System.IO.File]::WriteAllText($outPath, ($lines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Generated sitemap.xml ($($lines.Count - 2) URLs)" -ForegroundColor Green

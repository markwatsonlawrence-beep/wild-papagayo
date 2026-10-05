# ============================================================
# Wild Papagayo - IndexNow Submitter v1.0
# Pushes every URL in sitemap.xml to the IndexNow API (shared by
# Bing, Yandex, Seznam, Naver, ...) so those engines are notified
# of content immediately instead of waiting on their own crawl
# schedule. Google does not participate in IndexNow -- this is
# purely additive reach for Bing/Copilot/DuckDuckGo-class engines.
# Run AFTER the live site has actually been deployed (wrangler
# pages deploy), not before -- there is no point notifying an
# engine to fetch a URL that isn't live yet.
# Usage: .\indexnow-submit.ps1
# Requires: <key>.txt already published at the site root (deployed
# automatically -- it's just a public root .txt file).
# ============================================================
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$siteUrl = "https://wildpapagayo.com"
$key = "1d7a0f88720ac60791231611ae625f77"
$keyLocation = "$siteUrl/$key.txt"

$sitemapPath = Join-Path $root "sitemap.xml"
if (-not (Test-Path $sitemapPath)) { throw "sitemap.xml not found -- run sitemap-generator.ps1 first." }

# Plain regex extraction instead of [xml] DOM access -- the sitemap's default
# xmlns breaks PowerShell's dot-notation property access on <urlset>/<url>.
$sitemapText = Get-Content $sitemapPath -Raw
$urls = @([regex]::Matches($sitemapText, '<loc>([^<]+)</loc>') | ForEach-Object { $_.Groups[1].Value })
if ($urls.Count -eq 0) { throw "No URLs found in sitemap.xml." }

$body = @{
    host = "wildpapagayo.com"
    key = $key
    keyLocation = $keyLocation
    urlList = $urls
} | ConvertTo-Json -Depth 5

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri "https://api.indexnow.org/indexnow" -Method Post -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec 30 -UseBasicParsing
    Write-Host "IndexNow: submitted $($urls.Count) URLs -- status $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "IndexNow submission failed: $_" -ForegroundColor Yellow
}

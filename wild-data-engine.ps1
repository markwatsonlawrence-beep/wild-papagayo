[CmdletBinding()]
param(
    [ValidateSet('hotel')][string]$EntityType = 'hotel',
    [Parameter(Mandatory=$true)][string]$EntityId,
    [switch]$Offline,
    [switch]$ApplyAudit
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'engine/data/WildData.Core.ps1')

$sourcePath = Join-Path $root "knowledge/sources/$($EntityType)s/$EntityId.json"
if (-not (Test-Path $sourcePath)) { throw "Source configuration not found: $sourcePath" }
$config = [IO.File]::ReadAllText($sourcePath) | ConvertFrom-Json
$cacheDir = Join-Path $root "reports/imports/cache/$EntityType/$EntityId"
$outDir = Join-Path $root 'reports/imports'
$draftDir = Join-Path $root "knowledge/imports/$($EntityType)s"
New-Item -ItemType Directory -Force $outDir,$draftDir | Out-Null

Write-Host ""; Write-Host "WILD DATA ENGINE v1.0" -ForegroundColor Cyan
Write-Host "Entity: $($config.display_name)" -ForegroundColor White
Write-Host "Mode: $(if($Offline){'OFFLINE CACHE'}else{'LIVE OFFICIAL SOURCES'})" -ForegroundColor DarkGray

$sourceResults = @()
$allImages = @()
$allHeadings = @()
$allStructured = @()
$errors = @()

foreach ($source in @($config.sources | Sort-Object priority -Descending)) {
    Write-Host "- Fetching $($source.type): $($source.url)" -ForegroundColor Cyan
    try {
        $fetched = Invoke-WildSourceFetch -Source $source -AllowedDomains @($config.official_domains) -CacheDirectory $cacheDir -Offline:$Offline
        $html = $fetched.html
        $images = @(Get-WildImageCandidates -Html $html -BaseUrl $source.url)
        $headings = @(Get-WildHeadings -Html $html)
        $jsonLd = @(Get-WildJsonLd -Html $html)
        $signals = Get-WildKeywordSignals -Html $html
        $result = [ordered]@{
            source_id = $source.id
            source_type = $source.type
            requested_url = $source.url
            canonical_url = Get-WildCanonical -Html $html -BaseUrl $source.url
            http_status = $fetched.status
            fetched_at = (Get-Date).ToString('o')
            content_sha256 = $fetched.sha256
            title = Get-WildTitle $html
            meta_description = Get-WildMetaValue $html 'description'
            og_title = Get-WildMetaValue $html 'og:title'
            og_description = Get-WildMetaValue $html 'og:description'
            headings = $headings
            keyword_signals = $signals
            structured_data_count = $jsonLd.Count
            image_candidate_count = $images.Count
        }
        $sourceResults += [pscustomobject]$result
        foreach ($img in $images) { $img | Add-Member -NotePropertyName source_id -NotePropertyValue $source.id -Force; $allImages += $img }
        foreach ($h in $headings) { $h | Add-Member -NotePropertyName source_id -NotePropertyValue $source.id -Force; $allHeadings += $h }
        foreach ($j in $jsonLd) { $allStructured += [pscustomobject]@{ source_id=$source.id; data=$j } }
        Write-Host "  OK: $($images.Count) image candidates, $($headings.Count) headings" -ForegroundColor Green
    } catch {
        $errors += [pscustomobject]@{ source_id=$source.id; url=$source.url; error=$_.Exception.Message }
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$uniqueImages = @($allImages | Group-Object url | ForEach-Object { $_.Group | Select-Object -First 1 })
$gallerySummary = [ordered]@{}
foreach ($group in ($uniqueImages | Group-Object category)) { $gallerySummary[$group.Name] = $group.Count }

$draft = [ordered]@{
    engine_version = '1.0.0'
    generated_at = (Get-Date).ToString('o')
    entity_type = $config.entity_type
    entity_id = $config.entity_id
    display_name = $config.display_name
    status = 'pending_human_review'
    publishing_allowed = $false
    official_domains = @($config.official_domains)
    source_results = @($sourceResults)
    structured_data = @($allStructured)
    detected_headings = @($allHeadings | Select-Object -Unique source_id,level,text)
    gallery_candidates = @($uniqueImages)
    gallery_summary = [pscustomobject]$gallerySummary
    errors = @($errors)
    compliance = [ordered]@{
        source_text_copied = $false
        images_downloaded = $false
        image_usage_requires_permission = $true
        human_approval_required = $true
    }
}

$draftPath = Join-Path $draftDir "$EntityId-draft.json"
$draft | ConvertTo-Json -Depth 20 | Set-Content -Path $draftPath -Encoding UTF8

$txtPath = Join-Path $outDir "$EntityId-data-report.txt"
$lines = @(
    'Wild Data Engine Report',
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "Entity: $($config.display_name)",
    "Sources successful: $($sourceResults.Count)",
    "Sources failed: $($errors.Count)",
    "Image candidates: $($uniqueImages.Count)",
    "Draft: $draftPath",
    '',
    'IMPORTANT',
    '- The engine does not download or publish official hotel photographs.',
    '- Every image candidate remains permission_required until approved.',
    '- The generated JSON is a research draft and requires human review.'
)
$lines | Set-Content -Path $txtPath -Encoding UTF8

if ($ApplyAudit) {
    $hotelPath = Join-Path $root "knowledge/hotels/$EntityId.json"
    if (-not (Test-Path $hotelPath)) { throw "Approved hotel record not found: $hotelPath" }
    $backup = "$hotelPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $hotelPath $backup
    $hotel = [IO.File]::ReadAllText($hotelPath) | ConvertFrom-Json
    $audit = [ordered]@{
        data_engine_version='1.0.0'
        last_checked=(Get-Date).ToString('yyyy-MM-dd')
        successful_sources=$sourceResults.Count
        failed_sources=$errors.Count
        gallery_candidates=$uniqueImages.Count
        draft_path=(Resolve-Path $draftPath).Path
        status='pending_editorial_review'
    }
    $hotel | Add-Member -NotePropertyName source_audit -NotePropertyValue ([pscustomobject]$audit) -Force
    $hotel | ConvertTo-Json -Depth 20 | Set-Content -Path $hotelPath -Encoding UTF8
    Write-Host "Audit metadata applied. Backup: $backup" -ForegroundColor Yellow
}

Write-Host ""; Write-Host "Wild Data Engine completed." -ForegroundColor Green
Write-Host "Draft: $draftPath"
Write-Host "Report: $txtPath"
Write-Host "Images were detected only; none were downloaded or published." -ForegroundColor Yellow
if ($errors.Count -gt 0) { exit 2 }

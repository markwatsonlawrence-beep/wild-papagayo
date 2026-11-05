param(
    [ValidateSet('hotel')][string]$EntityType = 'hotel',
    [Parameter(Mandatory=$true)][string]$EntityId
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'engine\intelligence\WildIntelligence.Core.ps1')

function Test-ExperienceGuide {
    param($Guide)
    $Warnings = @()
    if ([string]::IsNullOrWhiteSpace([string]$Guide.editorial.description)) {
        $Warnings += "Missing description"
    }
    if (-not $Guide.editorial.why_stay_here) {
        $Warnings += "Missing Why Stay Here"
    }
    if (-not $Guide.experience_highlights) {
        $Warnings += "Missing Experience Highlights"
    }
    if (-not $Guide.local_tips) {
        $Warnings += "Missing Local Tips"
    }
    if (-not $Guide.suggested_stay) {
        $Warnings += "Missing Suggested Stay"
    }
    if (-not $Guide.location.transfer) {
        $Warnings += "Missing Transportation"
    }
    if (-not $Guide.recommendations.featured_tours) {
        $Warnings += "Missing Recommended Tours"
    }
    if (-not $Guide.faq) {
        $Warnings += "Missing FAQ"
    }
    return $Warnings
}

$errors = @()
$masterPath = Join-Path $root "knowledge\master\hotels\$EntityId.json"
try { $m = Read-JsonFile $masterPath } catch { $errors += $_.Exception.Message; $m = $null }

if ($m) {
    foreach ($section in @('identity','location','official_sources','official_facts','editorial','wild_insights','recommendations','faq','seo','verification','workflow')) {
        if ($null -eq $m.PSObject.Properties[$section] -or $null -eq $m.$section) { $errors += "Missing required section: $section" }
    }
    if ([string]::IsNullOrWhiteSpace([string]$m.identity.id)) { $errors += 'identity.id is required' }
    if ($m.identity.id -ne $EntityId) { $errors += "identity.id '$($m.identity.id)' does not match EntityId '$EntityId'" }
    if ((ConvertTo-SafeArray $m.official_sources).Count -eq 0) { $errors += 'At least one official source is required' }

    $destinationId = [string]$m.location.destination_id
    if ($destinationId) {
        $destinationFile = Join-Path $root "knowledge\destinations\$destinationId.json"
        if (-not (Test-Path $destinationFile)) { $errors += "Destination not found: $destinationId" }
    }
    $airports = Read-JsonFile (Join-Path $root 'knowledge\airports.json')
    $airportIds = @($airports | ForEach-Object { [string]$_.id })
    if ($airportIds -notcontains [string]$m.location.airport_id) { $errors += "Airport not found: $($m.location.airport_id)" }

    foreach ($tourId in (ConvertTo-SafeArray $m.recommendations.featured_tours)) {
        if (-not (Test-Path (Join-Path $root "knowledge\tours\$tourId.json"))) { $errors += "Featured tour not found: $tourId" }
    }
}

if ($errors.Count -gt 0) {
    Write-Host 'Wild Intelligence validation FAILED.' -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "ERROR: $_" -ForegroundColor Red }
    exit 1
}

$Warnings = @()
if ($m) { $Warnings = @(Test-ExperienceGuide $m) }

$Sections  = 8
$Completed = $Sections - $Warnings.Count
$Score     = [math]::Round(($Completed / $Sections) * 100, 1)

if ($Warnings.Count -eq 0) {
    Write-Host 'Experience Guide validation passed.' -ForegroundColor Green
} else {
    Write-Host ''
    Write-Host 'Guide requires attention:' -ForegroundColor Yellow
    foreach ($Warning in $Warnings) {
        Write-Host " - $Warning"
    }
}

Write-Host ''
Write-Host "Experience Guide Quality: $Score%"
exit 0

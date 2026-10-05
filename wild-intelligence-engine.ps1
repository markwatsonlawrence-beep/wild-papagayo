param(
    [ValidateSet('hotel')][string]$EntityType = 'hotel',
    [Parameter(Mandatory=$true)][string]$EntityId,
    [switch]$PublishLegacy,
    [switch]$ReportOnly
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'engine\intelligence\WildIntelligence.Core.ps1')

$masterPath = Join-Path $root "knowledge\master\hotels\$EntityId.json"
$legacyPath = Join-Path $root "knowledge\hotels\$EntityId.json"
$reportDir = Join-Path $root 'reports\intelligence'
$reportPath = Join-Path $reportDir "$EntityId-quality-report.txt"
$reportJsonPath = Join-Path $reportDir "$EntityId-quality-report.json"

if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Force -Path $reportDir | Out-Null }

Write-Host ''
Write-Host 'WILD INTELLIGENCE ENGINE v2.0' -ForegroundColor Cyan
Write-Host "Entity: $EntityType/$EntityId"

$master = Read-JsonFile $masterPath
$quality = Get-HotelQualityScore -Master $master -ProjectRoot $root

$lines = @()
$lines += 'Wild Intelligence - Hotel Quality Report'
$lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += "Entity: $EntityId"
$lines += ''
foreach ($key in $quality.Sections.Keys) {
    $value = $quality.Sections[$key]
    $lines += ('{0,-24} {1,6}%' -f $key, $value)
}
$lines += ''
$lines += "OVERALL QUALITY: $($quality.Overall)%"
$threshold = [double](Get-ObjectPropertyValue $master.workflow 'publication_threshold' 90)
$ready = ($quality.Overall -ge $threshold)
$lines += "PUBLICATION THRESHOLD: $threshold%"
$lines += "READY TO PUBLISH: $(if ($ready) { 'YES' } else { 'NO' })"

[System.IO.File]::WriteAllLines($reportPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-JsonFile -Data ([ordered]@{
    entity_id = $EntityId
    generated = (Get-Date).ToString('s')
    overall = $quality.Overall
    threshold = $threshold
    ready_to_publish = $ready
    sections = $quality.Sections
}) -Path $reportJsonPath

if ($PublishLegacy -and -not $ReportOnly) {
    $legacy = Convert-MasterToLegacyHotel -Master $master
    Write-JsonFile -Data $legacy -Path $legacyPath
    Write-Host "Legacy hotel profile updated: $legacyPath" -ForegroundColor Green
}

foreach ($key in $quality.Sections.Keys) {
    $value = $quality.Sections[$key]
    $color = if ($value -ge 90) { 'Green' } elseif ($value -ge 70) { 'Yellow' } else { 'Red' }
    Write-Host ('- {0,-24} {1,6}%' -f $key, $value) -ForegroundColor $color
}
Write-Host ''
Write-Host "Overall quality: $($quality.Overall)%" -ForegroundColor $(if ($ready) { 'Green' } else { 'Yellow' })
Write-Host "Report: $reportPath"
if (-not $ready) { Write-Host 'Status: REVIEW REQUIRED before publication.' -ForegroundColor Yellow }
else { Write-Host 'Status: Publication quality threshold passed.' -ForegroundColor Green }

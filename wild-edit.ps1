param(
    [ValidateSet('hotel')][string]$EntityType = 'hotel',
    [Parameter(Mandatory=$true)][string]$EntityId
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'engine\intelligence\WildIntelligence.Core.ps1')
$masterPath = Join-Path $root "knowledge\master\hotels\$EntityId.json"
$m = Read-JsonFile $masterPath
$q = Get-HotelQualityScore -Master $m -ProjectRoot $root

Write-Host ''
Write-Host 'WILD EDITOR MODE' -ForegroundColor Cyan
Write-Host "$($m.identity.official_name)" -ForegroundColor White
Write-Host ('-' * 58)
foreach ($key in $q.Sections.Keys) {
    $value = $q.Sections[$key]
    $state = if ($value -ge 90) { 'OK' } elseif ($value -ge 70) { 'REVIEW' } else { 'MISSING' }
    $color = if ($value -ge 90) { 'Green' } elseif ($value -ge 70) { 'Yellow' } else { 'Red' }
    Write-Host ('{0,-24} {1,6}%  {2}' -f $key, $value, $state) -ForegroundColor $color
}
Write-Host ('-' * 58)
Write-Host "Overall quality: $($q.Overall)%"
Write-Host "Workflow status: $($m.workflow.status)"
Write-Host "Last verified: $($m.verification.last_verified)"
Write-Host ''
Write-Host "Master record: $masterPath"
Write-Host 'To update the compatible Hotel Engine profile after review:'
Write-Host ".\wild-intelligence-engine.ps1 -EntityType hotel -EntityId $EntityId -PublishLegacy" -ForegroundColor Cyan

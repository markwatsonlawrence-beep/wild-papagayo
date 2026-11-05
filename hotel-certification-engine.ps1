param(
    [string]$EntityId = 'all',
    [switch]$Open
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'engine\certification\WildCertification.Core.ps1')

$rulesPath = Join-Path $root 'knowledge\certification-rules\hotel-certification-rules.json'
$masterDir = Join-Path $root 'knowledge\master\hotels'
$outDir = Join-Path $root 'reports\certifications\hotels'
$knowledgeOutDir = Join-Path $root 'knowledge\certifications\hotels'

if (-not (Test-Path $rulesPath)) { throw "Certification rules not found: $rulesPath" }
if (-not (Test-Path $masterDir)) { throw "Master hotel directory not found: $masterDir" }
New-Item -ItemType Directory -Force -Path $outDir,$knowledgeOutDir | Out-Null

$rules = Get-Content $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$files = if ($EntityId -eq 'all') { @(Get-ChildItem $masterDir -Filter '*.json' -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' }) } else { @((Get-Item (Join-Path $masterDir "$EntityId.json"))) }
$summary = @()

foreach ($file in $files) {
    $master = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $result = Measure-WildHotelCertification -Master $master -Rules $rules
    $jsonPath = Join-Path $knowledgeOutDir ($result.entity_id + '.json')
    $txtPath = Join-Path $outDir ($result.entity_id + '-certification.txt')
    $htmlPath = Join-Path $outDir ($result.entity_id + '-certification.html')

    $result | ConvertTo-Json -Depth 12 | Set-Content $jsonPath -Encoding UTF8
    $text = @(
        'WILD HOTEL CERTIFICATION',
        "Hotel: $($result.entity_name)",
        "Score: $($result.overall_score)%",
        "Certification: $($result.certification)",
        "Publication ready: $($result.publication_ready)",
        '',
        'SECTIONS'
    )
    foreach ($section in @($result.sections)) { $text += "- $($section.name): $($section.percent)%" }
    $text += ''
    $text += 'BLOCKING ISSUES'
    if (@($result.blocking_issues).Count -eq 0) { $text += '- None' } else { foreach ($issue in @($result.blocking_issues)) { $text += "- $issue" } }
    $text | Set-Content $txtPath -Encoding UTF8
    ConvertTo-WildCertificationHtml $result | Set-Content $htmlPath -Encoding UTF8

    $summary += $result
    Write-Host "Hotel: $($result.entity_name)" -ForegroundColor Cyan
    Write-Host "Score: $($result.overall_score)% | Certification: $($result.certification) | Ready: $($result.publication_ready)" -ForegroundColor $(if($result.publication_ready){'Green'}else{'Yellow'})
}

$summaryPath = Join-Path $outDir 'hotel-certification-summary.json'
$summary | ConvertTo-Json -Depth 12 | Set-Content $summaryPath -Encoding UTF8
Write-Host "Report folder: $outDir" -ForegroundColor Green

if ($Open -and $summary.Count -eq 1) {
    Start-Process (Join-Path $outDir ($summary[0].entity_id + '-certification.html'))
}

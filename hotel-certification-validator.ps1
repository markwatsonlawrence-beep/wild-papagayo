param([string]$EntityId = 'all')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$rulesPath = Join-Path $root 'knowledge\certification-rules\hotel-certification-rules.json'
$masterDir = Join-Path $root 'knowledge\master\hotels'
$errors = @()
$warnings = @()

if (-not (Test-Path $rulesPath)) { $errors += "Missing rules file: $rulesPath" }
if (-not (Test-Path $masterDir)) { $errors += "Missing master hotels directory: $masterDir" }

if ($errors.Count -eq 0) {
    $files = if ($EntityId -eq 'all') { @(Get-ChildItem $masterDir -Filter '*.json' -File | Where-Object { $_.BaseName -notmatch '\.v\d+-backup-' }) } else { @(Get-Item (Join-Path $masterDir "$EntityId.json")) }
    foreach ($file in $files) {
        try { $master = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $errors += "$($file.Name): invalid JSON"; continue }
        foreach ($section in @('identity','location','official_facts','editorial','wild_insights','gallery','recommendations','seo','verification','workflow')) {
            if (-not $master.PSObject.Properties[$section]) { $warnings += "$($file.Name): missing '$section' section" }
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Host 'Hotel Certification validation failed.' -ForegroundColor Red
    foreach ($error in $errors) { Write-Host "ERROR: $error" -ForegroundColor Red }
    exit 1
}
Write-Host 'Hotel Certification validation passed.' -ForegroundColor Green
Write-Host "Warnings: $($warnings.Count)"
foreach ($warning in $warnings) { Write-Host "WARNING: $warning" -ForegroundColor Yellow }
exit 0

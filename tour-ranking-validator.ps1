param(
    [Parameter(Mandatory = $true)]
    [string]$HotelId
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$path = Join-Path $root "knowledge\recommendations\rankings\$HotelId-ranking.json"

if (-not (Test-Path $path)) {
    Write-Host "Tour Ranking validation FAILED." -ForegroundColor Red
    Write-Host "ERROR: Ranking file not found: $path"
    exit 1
}

$data = (
    [System.IO.File]::ReadAllText(
        $path,
        [System.Text.Encoding]::UTF8
    ) | ConvertFrom-Json
)

$errors = @()
$warnings = @()

if ([string]::IsNullOrWhiteSpace([string]$data.hotel_id)) {
    $errors += "Missing hotel_id"
}

$recommendations = @($data.recommendations)

if ($recommendations.Count -eq 0) {
    $errors += "No recommendations generated"
}

$duplicateIds = @(
    $recommendations |
    Group-Object tour_id |
    Where-Object Count -gt 1
)

if ($duplicateIds.Count -gt 0) {
    $errors += "Duplicate tour IDs found"
}

$invalidScores = @(
    $recommendations |
    Where-Object {
        [double]$_.score -lt 0 -or [double]$_.score -gt 100
    }
)

if ($invalidScores.Count -gt 0) {
    $errors += "Scores outside 0-100 range"
}

$notSorted = $false

for ($i = 1; $i -lt $recommendations.Count; $i++) {
    if ([double]$recommendations[$i].score -gt [double]$recommendations[$i - 1].score) {
        $notSorted = $true
        break
    }
}

if ($notSorted) {
    $errors += "Recommendations are not sorted descending"
}

$pickupMismatches = @(
    $recommendations |
    Where-Object { -not [bool]$_.pickup_compatible }
)

if ($pickupMismatches.Count -gt 0) {
    $warnings += "$($pickupMismatches.Count) recommendation(s) are not pickup-compatible"
}

if ($recommendations.Count -lt 5) {
    $warnings += "Fewer than 5 recommendations"
}

if ($errors.Count -gt 0) {
    Write-Host "Tour Ranking validation FAILED." -ForegroundColor Red

    foreach ($errorMessage in $errors) {
        Write-Host "ERROR: $errorMessage"
    }

    exit 1
}

Write-Host "Tour Ranking validation passed." -ForegroundColor Green
Write-Host "Hotel: $HotelId"
Write-Host "Recommendations: $($recommendations.Count)"
Write-Host "Warnings: $($warnings.Count)"

foreach ($warning in $warnings) {
    Write-Host "WARNING: $warning" -ForegroundColor Yellow
}

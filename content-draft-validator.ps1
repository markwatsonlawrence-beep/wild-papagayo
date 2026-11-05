param(
    [Parameter(Mandatory = $true)]
    [string]$Slug
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$path = Join-Path $root "knowledge\content\drafts\$Slug.json"

if (-not (Test-Path $path)) {
    Write-Host "Content validation FAILED." -ForegroundColor Red
    Write-Host "ERROR: Draft not found: $path"
    exit 1
}

$article = (
    [System.IO.File]::ReadAllText(
        $path,
        [System.Text.Encoding]::UTF8
    ) | ConvertFrom-Json
)

$errors = @()
$warnings = @()

$required = @(
    "slug",
    "title",
    "excerpt",
    "seo_title_pro",
    "seo_description",
    "content_block_1",
    "content_block_2",
    "content_block_3",
    "content_block_faq",
    "cta_url",
    "cta_text"
)

foreach ($field in $required) {
    $property = $article.PSObject.Properties[$field]

    if (
        -not $property -or
        [string]::IsNullOrWhiteSpace([string]$property.Value)
    ) {
        $errors += "Missing required field: $field"
    }
}

if ([string]$article.seo_title_pro -and ([string]$article.seo_title_pro).Length -gt 65) {
    $warnings += "SEO title is longer than 65 characters"
}

if ([string]$article.seo_description -and ([string]$article.seo_description).Length -gt 160) {
    $warnings += "SEO description is longer than 160 characters"
}

$placeholderPatterns = @(
    "Editorial draft:",
    "Replace this placeholder",
    "Requires editorial"
)

$placeholderCount = 0
$raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)

foreach ($pattern in $placeholderPatterns) {
    if ($raw -match [regex]::Escape($pattern)) {
        $placeholderCount++
    }
}

if ($placeholderCount -gt 0) {
    $warnings += "Draft still contains editorial placeholders"
}

if (@($article.internal_links).Count -eq 0) {
    $warnings += "No internal links detected"
}

if (@($article.tour_ids).Count -eq 0 -and @($article.hotel_ids).Count -eq 0 -and @($article.destination_ids).Count -eq 0) {
    $warnings += "Draft is not linked to any knowledge entity"
}

if ($errors.Count -gt 0) {
    Write-Host "Content validation FAILED." -ForegroundColor Red

    foreach ($errorMessage in $errors) {
        Write-Host "ERROR: $errorMessage"
    }

    exit 1
}

Write-Host "Content draft validation passed." -ForegroundColor Green
Write-Host "Slug: $Slug"
Write-Host "Warnings: $($warnings.Count)"

foreach ($warning in $warnings) {
    Write-Host "WARNING: $warning" -ForegroundColor Yellow
}

# Wild Papagayo Knowledge Graph Validator v1.0
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$knowledgeDir = Join-Path $root 'knowledge'
$blogPath = Join-Path $root 'blog-data.json'
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Read-JsonFile([string]$path) {
    if (-not (Test-Path $path)) {
        $errors.Add("Missing file: $path")
        return @()
    }
    try {
        return (Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json)
    } catch {
        $errors.Add("Invalid JSON: $path :: $($_.Exception.Message)")
        return @()
    }
}

$files = @{
    destination = 'destinations.json'
    hotel = 'hotels.json'
    tour = 'tours.json'
    airport = 'airports.json'
    activity = 'activities.json'
    season = 'seasons.json'
    traveler_profile = 'traveler-profiles.json'
    transportation = 'transportation.json'
}

$sets = @{}
foreach ($type in $files.Keys) {
    $items = @(Read-JsonFile (Join-Path $knowledgeDir $files[$type]))
    $ids = @($items | ForEach-Object { $_.id })
    $duplicates = @($ids | Group-Object | Where-Object Count -gt 1)
    foreach ($dup in $duplicates) { $errors.Add("Duplicate $type ID: $($dup.Name)") }
    $sets[$type] = @{}
    foreach ($id in $ids) { if ($id) { $sets[$type][$id] = $true } }
}

$articles = @(Read-JsonFile $blogPath)
$articleFields = @{
    destination_ids = 'destination'
    hotel_ids = 'hotel'
    tour_ids = 'tour'
    activity_ids = 'activity'
    season_ids = 'season'
    traveler_profile_ids = 'traveler_profile'
}
foreach ($a in $articles) {
    foreach ($field in $articleFields.Keys) {
        foreach ($id in @($a.$field)) {
            $type = $articleFields[$field]
            if ($id -and -not $sets[$type].ContainsKey([string]$id)) {
                $errors.Add("Article '$($a.slug)' references missing $type ID '$id' in $field")
            }
        }
    }
}

$tours = @(Read-JsonFile (Join-Path $knowledgeDir 'tours.json'))
foreach ($tour in $tours) {
    if ($tour.page_url -and $tour.page_url.StartsWith('../')) {
        $relative = $tour.page_url.Substring(3).Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path (Join-Path $root $relative))) {
            $errors.Add("Tour page missing for '$($tour.id)': $($tour.page_url)")
        }
    }
    foreach ($id in @($tour.destination_ids)) {
        if (-not $sets.destination.ContainsKey([string]$id)) {
            $errors.Add("Tour '$($tour.id)' references missing destination '$id'")
        }
    }
    foreach ($id in @($tour.activity_ids)) {
        if (-not $sets.activity.ContainsKey([string]$id)) {
            $errors.Add("Tour '$($tour.id)' references missing activity '$id'")
        }
    }
}

$hotels = @(Read-JsonFile (Join-Path $knowledgeDir 'hotels.json'))
foreach ($hotel in $hotels) {
    if ($hotel.destination_id -and -not $sets.destination.ContainsKey([string]$hotel.destination_id)) {
        $errors.Add("Hotel '$($hotel.id)' references missing destination '$($hotel.destination_id)'")
    }
}

$reportPath = Join-Path $root 'knowledge-validation-report.txt'
$lines = @(
    'Wild Papagayo Knowledge Graph Validation',
    ('Generated: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
    '',
    "Articles: $($articles.Count)",
    "Destinations: $($sets.destination.Count)",
    "Hotels: $($sets.hotel.Count)",
    "Tours: $($sets.tour.Count)",
    "Activities: $($sets.activity.Count)",
    '',
    "Errors: $($errors.Count)",
    "Warnings: $($warnings.Count)"
)
if ($errors.Count -gt 0) { $lines += ''; $lines += 'ERRORS'; $lines += $errors }
if ($warnings.Count -gt 0) { $lines += ''; $lines += 'WARNINGS'; $lines += $warnings }
$lines | Set-Content -Encoding UTF8 $reportPath

if ($errors.Count -gt 0) {
    Write-Host "Validation failed with $($errors.Count) error(s). See knowledge-validation-report.txt" -ForegroundColor Red
    exit 1
}
Write-Host 'Knowledge Graph validation passed.' -ForegroundColor Green
Write-Host "Report: knowledge-validation-report.txt"

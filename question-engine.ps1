# ============================================================
# Wild Papagayo — Question Engine v1.0
# Validates the editorial question database and creates:
# - question-engine-report.txt
# - question-editorial-queue.csv
# Usage: .\question-engine.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$questionPath = Join-Path $root "questions\questions.json"
$metaPath = Join-Path $root "questions\meta.json"
$blogPath = Join-Path $root "blog-data.json"
$knowledgeDir = Join-Path $root "knowledge"
$reportPath = Join-Path $root "question-engine-report.txt"
$queuePath = Join-Path $root "question-editorial-queue.csv"

function Read-JsonFile([string]$path) {
    if (-not (Test-Path $path)) { throw "Missing required file: $path" }
    return ([System.IO.File]::ReadAllText($path) | ConvertFrom-Json)
}

function Normalize-Array($value) {
    if ($null -eq $value) { return @() }
    return @($value)
}

$meta = Read-JsonFile $metaPath
$questions = @(Read-JsonFile $questionPath)
$articles = @(Read-JsonFile $blogPath)

$entityFiles = @{
    destination_ids      = "destinations.json"
    hotel_ids            = "hotels.json"
    tour_ids             = "tours.json"
    activity_ids         = "activities.json"
    season_ids           = "seasons.json"
    traveler_profile_ids = "traveler-profiles.json"
    transportation_ids   = "transportation.json"
}

$validEntityIds = @{}
foreach ($property in $entityFiles.Keys) {
    $entities = @(Read-JsonFile (Join-Path $knowledgeDir $entityFiles[$property]))
    $validEntityIds[$property] = @($entities | ForEach-Object { $_.id })
}

$allowedStatuses = @($meta.status_values)
$allowedIntents = @($meta.intent_values)
$allowedSources = @($meta.source_values)
$articleSlugs = @($articles | ForEach-Object { $_.slug })
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

# Duplicate IDs
$duplicateIds = $questions | Group-Object id | Where-Object { $_.Count -gt 1 }
foreach ($duplicate in $duplicateIds) {
    $errors.Add("Duplicate question ID: $($duplicate.Name)")
}

foreach ($q in $questions) {
    $prefix = "[$($q.id)]"

    if (-not $q.id -or $q.id -notmatch '^q-[a-z0-9]+(?:-[a-z0-9]+)*$') {
        $errors.Add("$prefix Invalid ID. Use q-lowercase-kebab-case.")
    }
    if (-not $q.question) { $errors.Add("$prefix Missing question.") }
    if (-not $q.working_title) { $warnings.Add("$prefix Missing working_title.") }
    if ($allowedStatuses -notcontains $q.status) { $errors.Add("$prefix Invalid status '$($q.status)'.") }
    if ($allowedIntents -notcontains $q.intent) { $errors.Add("$prefix Invalid intent '$($q.intent)'.") }
    if ($allowedSources -notcontains $q.source) { $errors.Add("$prefix Invalid source '$($q.source)'.") }

    $priority = 0
    if (-not [int]::TryParse([string]$q.priority, [ref]$priority) -or $priority -lt 1 -or $priority -gt 100) {
        $errors.Add("$prefix Priority must be an integer from 1 to 100.")
    }

    foreach ($property in $entityFiles.Keys) {
        foreach ($id in (Normalize-Array $q.$property)) {
            if ($validEntityIds[$property] -notcontains $id) {
                $errors.Add("$prefix Unknown $property reference: '$id'.")
            }
        }
    }

    if ($q.status -eq "published") {
        if (-not $q.article_slug) {
            $errors.Add("$prefix Published question requires article_slug.")
        } elseif ($articleSlugs -notcontains $q.article_slug) {
            $errors.Add("$prefix article_slug '$($q.article_slug)' does not exist in blog-data.json.")
        }
    } elseif ($q.article_slug -and $articleSlugs -notcontains $q.article_slug) {
        $warnings.Add("$prefix article_slug '$($q.article_slug)' is not yet present in blog-data.json.")
    }

    if ((Normalize-Array $q.destination_ids).Count -eq 0 -and
        (Normalize-Array $q.hotel_ids).Count -eq 0 -and
        (Normalize-Array $q.tour_ids).Count -eq 0) {
        $warnings.Add("$prefix No destination, hotel or tour entity assigned.")
    }
}

# Detect one article connected to multiple questions. Allowed, but useful to review.
$publishedWithSlug = $questions | Where-Object { $_.article_slug }
$sharedSlugs = $publishedWithSlug | Group-Object article_slug | Where-Object { $_.Count -gt 1 }
foreach ($shared in $sharedSlugs) {
    $warnings.Add("Multiple questions point to article '$($shared.Name)' ($($shared.Count) questions).")
}

$statusCounts = $questions | Group-Object status | Sort-Object Name
$sourceCounts = $questions | Group-Object source | Sort-Object Name
$topQueue = @($questions | Where-Object { $_.status -notin @('published','archived') } | Sort-Object @{Expression='priority';Descending=$true}, @{Expression='id';Descending=$false})

$report = New-Object System.Collections.Generic.List[string]
$report.Add("Wild Papagayo Question Engine Report")
$report.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("Questions: $($questions.Count)")
$report.Add("Errors: $($errors.Count)")
$report.Add("Warnings: $($warnings.Count)")
$report.Add("")
$report.Add("STATUS COUNTS")
foreach ($row in $statusCounts) { $report.Add("- $($row.Name): $($row.Count)") }
$report.Add("")
$report.Add("SOURCE COUNTS")
foreach ($row in $sourceCounts) { $report.Add("- $($row.Name): $($row.Count)") }
$report.Add("")
$report.Add("TOP EDITORIAL PRIORITIES")
foreach ($q in ($topQueue | Select-Object -First 10)) {
    $report.Add("- [$($q.priority)] $($q.working_title) | status=$($q.status) | id=$($q.id)")
}
$report.Add("")
$report.Add("ERRORS")
if ($errors.Count -eq 0) { $report.Add("- None") } else { foreach ($e in $errors) { $report.Add("- $e") } }
$report.Add("")
$report.Add("WARNINGS")
if ($warnings.Count -eq 0) { $report.Add("- None") } else { foreach ($w in $warnings) { $report.Add("- $w") } }

[System.IO.File]::WriteAllLines($reportPath, $report, [System.Text.UTF8Encoding]::new($false))

$topQueue | Select-Object `
    @{Name='priority';Expression={$_.priority}},
    @{Name='status';Expression={$_.status}},
    @{Name='question_id';Expression={$_.id}},
    @{Name='working_title';Expression={$_.working_title}},
    @{Name='intent';Expression={$_.intent}},
    @{Name='source';Expression={$_.source}},
    @{Name='destinations';Expression={($_.destination_ids -join '|')}},
    @{Name='hotels';Expression={($_.hotel_ids -join '|')}},
    @{Name='tours';Expression={($_.tour_ids -join '|')}},
    @{Name='business_goal';Expression={$_.business_goal}} |
    Export-Csv -Path $queuePath -NoTypeInformation -Encoding UTF8

if ($errors.Count -gt 0) {
    Write-Host "Question Engine validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    Write-Host "Report: question-engine-report.txt"
    exit 1
}

Write-Host "Question Engine validation passed." -ForegroundColor Green
Write-Host "Questions: $($questions.Count) | Editorial queue: $($topQueue.Count) | Warnings: $($warnings.Count)"
Write-Host "Report: question-engine-report.txt"
Write-Host "Queue: question-editorial-queue.csv"

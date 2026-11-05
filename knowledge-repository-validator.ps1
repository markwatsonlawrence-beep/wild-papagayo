# Wild Engine - Knowledge Repository Validator v2
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$knowledge = Join-Path $root "knowledge"
$destinationDir = Join-Path $knowledge "destinations"
$reportPath = Join-Path $root "knowledge-repository-report.txt"

function Read-Utf8Json([string]$path) {
  return ([System.IO.File]::ReadAllText($path) | ConvertFrom-Json)
}

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

$airports = @(Read-Utf8Json (Join-Path $knowledge "airports.json"))
$tours = @(Read-Utf8Json (Join-Path $knowledge "tours.json"))
$airportIds = @($airports | ForEach-Object { [string]$_.id })
$tourIds = @($tours | ForEach-Object { [string]$_.id })
$destinationFiles = @(Get-ChildItem $destinationDir -Filter *.json | Sort-Object Name)
$destinationIds = @($destinationFiles | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })

foreach ($file in $destinationFiles) {
  try { $d = Read-Utf8Json $file.FullName }
  catch { $errors.Add("$($file.Name): invalid JSON - $($_.Exception.Message)"); continue }

  foreach ($field in @('id','name','hero_image','description','province','airport_id')) {
    if (-not $d.$field) { $errors.Add("$($file.Name): missing required field '$field'") }
  }

  if ($d.id -ne [System.IO.Path]::GetFileNameWithoutExtension($file.Name)) {
    [void]$errors.Add("$($file.Name): id '$($d.id)' must match the filename")
  }

  if ($d.airport_id -and $airportIds -notcontains [string]$d.airport_id) {
    [void]$errors.Add("$($file.Name): unknown airport_id '$($d.airport_id)'")
  }

  $heroPath = Join-Path $root ([string]$d.hero_image)
  if ($d.hero_image -and -not (Test-Path $heroPath)) {
    [void]$errors.Add("$($file.Name): missing hero image '$($d.hero_image)'")
  }

  foreach ($tourId in @($d.featured_tours)) {
    if ($tourIds -notcontains [string]$tourId) {
      [void]$errors.Add("$($file.Name): unknown featured tour '$tourId'")
    }
    $tourPage = Join-Path $root "tours/$tourId.html"
    if (-not (Test-Path $tourPage)) {
      [void]$errors.Add("$($file.Name): tour page not found 'tours/$tourId.html'")
    }
  }

  foreach ($nearbyId in @($d.nearby)) {
    if ($destinationIds -notcontains [string]$nearbyId) {
      [void]$warnings.Add("$($file.Name): nearby destination '$nearbyId' has no generated destination file yet")
    }
  }

  if (-not $d.why_visit -or $d.why_visit.Count -lt 2) {
    [void]$warnings.Add("$($file.Name): add at least 2 why_visit paragraphs")
  }
  if (-not $d.faq -or $d.faq.Count -lt 4) {
    [void]$warnings.Add("$($file.Name): add at least 4 FAQ entries")
  }
}

$lines = New-Object System.Collections.Generic.List[string]
[void]$lines.Add("Wild Engine - Knowledge Repository Report")
[void]$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$lines.Add("Destinations: $($destinationFiles.Count)")
[void]$lines.Add("Airports: $($airports.Count)")
[void]$lines.Add("Tours: $($tours.Count)")
[void]$lines.Add("Errors: $($errors.Count)")
[void]$lines.Add("Warnings: $($warnings.Count)")
[void]$lines.Add("")
if ($errors.Count -gt 0) {
  [void]$lines.Add("ERRORS")
  foreach ($e in $errors) { [void]$lines.Add("- $e") }
  [void]$lines.Add("")
}
if ($warnings.Count -gt 0) {
  [void]$lines.Add("WARNINGS")
  foreach ($w in $warnings) { [void]$lines.Add("- $w") }
  [void]$lines.Add("")
}
if ($errors.Count -eq 0) { $lines.Add("Validation passed.") }
[System.IO.File]::WriteAllLines($reportPath, [string[]]$lines.ToArray(), [System.Text.UTF8Encoding]::new($false))

if ($errors.Count -gt 0) {
  Write-Host "Knowledge Repository validation failed: $($errors.Count) error(s)." -ForegroundColor Red
  Write-Host "Report: knowledge-repository-report.txt"
  exit 1
}
Write-Host "Knowledge Repository validation passed." -ForegroundColor Green
Write-Host "Destinations: $($destinationFiles.Count) | Airports: $($airports.Count) | Tours: $($tours.Count)"
Write-Host "Warnings: $($warnings.Count)"
Write-Host "Report: knowledge-repository-report.txt"

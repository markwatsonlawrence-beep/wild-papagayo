# Wild Papagayo - Tour Knowledge Graph Validator
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$tourDir = Join-Path $root 'knowledge\tours'
$indexPath = Join-Path $root 'knowledge\tours-index.json'
$destPath = Join-Path $root 'knowledge\destinations.json'
$actPath = Join-Path $root 'knowledge\activities.json'
$hotelDir = Join-Path $root 'knowledge\hotels'
$policyPath = Join-Path $root 'knowledge\policies\booking-cancellation.json'
$errors = @()
$warnings = @()

# ---- Booking/cancellation policy: single central source of truth (replaces the 33 former
# per-tour copies). This section guards against the two regressions that matter most: the central
# file disappearing/breaking, and a tour silently reintroducing a hard-coded policy copy. ----
if (-not (Test-Path $policyPath)) {
  $errors += "knowledge/policies/booking-cancellation.json is missing -- this is the single source of truth for the tour booking/cancellation policy; tour-generator.ps1 cannot run without it."
} else {
  try {
    $policy = [System.IO.File]::ReadAllText($policyPath) | ConvertFrom-Json
    if ($null -eq $policy.version) { $errors += "knowledge/policies/booking-cancellation.json: missing 'version'." }
    if (-not $policy.reservation_policy_core) { $errors += "knowledge/policies/booking-cancellation.json: missing or empty 'reservation_policy_core'." }
    if (-not $policy.reservation_policy_noshow) { $errors += "knowledge/policies/booking-cancellation.json: missing or empty 'reservation_policy_noshow'." }
    if (-not $policy.cancellation_faq -or -not $policy.cancellation_faq.question -or -not $policy.cancellation_faq.answer) {
      $errors += "knowledge/policies/booking-cancellation.json: 'cancellation_faq' must have both a non-empty 'question' and 'answer'."
    }
  } catch { $errors += "knowledge/policies/booking-cancellation.json: invalid JSON - $($_.Exception.Message)" }
}
# Legacy/old-policy wording that must never reappear in an active tour source (the pre-centralization
# policy used these; their presence here means someone hand-edited stale wording back in).
$oldPolicyPatterns = @('48 hours', '48-hour', '7 days', 'seven days', '50% refund')

if (-not (Test-Path $tourDir)) { throw "Missing folder: $tourDir" }
$tours = @()
Get-ChildItem $tourDir -Filter '*.json' | Sort-Object Name | ForEach-Object {
  $rawText = [System.IO.File]::ReadAllText($_.FullName)
  try {
    $obj = $rawText | ConvertFrom-Json
    $obj | Add-Member -NotePropertyName '__file' -NotePropertyValue $_.Name -Force
    $tours += $obj
    if ($obj.page_content -and $obj.page_content.accordion -and ($obj.page_content.accordion.PSObject.Properties.Name -contains 'reservation_policy')) {
      $errors += "$($_.Name): page_content.accordion.reservation_policy has reappeared -- this field was retired by the booking-policy centralization; policy text belongs in knowledge/policies/booking-cancellation.json, with only tour-specific riders in reservation_policy_extra."
    }
    if ($obj.page_content -and ($obj.page_content.PSObject.Properties.Name -contains 'seo_title_override' -or $obj.page_content.PSObject.Properties.Name -contains 'seo_description_override')) {
      $errors += "$($_.Name): page_content.seo_title_override/seo_description_override found -- the only canonical location is root-level (see knowledge/tour-schema.json); tour-generator.ps1 no longer reads this nested location, so a value placed here is silently ignored. Move it to the root level."
    }
    # Retired duplicate-source fields from the structural content-debt cleanup --
    # each one used to let a tour's own page silently diverge from its
    # canonical value. Reintroducing any of them (even with a correct-looking
    # value) recreates exactly that drift risk, so this is a hard fail, not a
    # semantic check.
    if ($obj.PSObject.Properties.Name -contains 'included') {
      $errors += "$($_.Name): top-level 'included' has reappeared -- this field was retired; the public/canonical source is page_content.everything_included (also read by article-auto-draft.ps1 and Start-Wild-CMS.ps1)."
    }
    if ($obj.PSObject.Properties.Name -contains 'what_to_bring') {
      $errors += "$($_.Name): top-level 'what_to_bring' has reappeared -- this field was retired; the public/canonical source is page_content.what_to_pack."
    }
    if ($obj.page_content -and $obj.page_content.quick_stats -and ($obj.page_content.quick_stats.PSObject.Properties.Name -contains 'difficulty')) {
      $errors += "$($_.Name): page_content.quick_stats.difficulty has reappeared -- this field was retired; the canonical source is the root-level 'difficulty' field."
    }
    if ($obj.page_content -and $obj.page_content.quick_stats -and ($obj.page_content.quick_stats.PSObject.Properties.Name -contains 'duration')) {
      $errors += "$($_.Name): page_content.quick_stats.duration has reappeared -- this field was retired; the canonical source is intelligence.duration_type (short badge) / duration_label (long form)."
    }
  } catch { $errors += "$($_.Name): invalid JSON - $($_.Exception.Message)" }
  foreach ($pattern in $oldPolicyPatterns) {
    if ($rawText -match [regex]::Escape($pattern)) { $errors += "$($_.Name): contains old-policy wording '$pattern' -- the active policy is 25% deposit / 72 hours; this looks like a regression to the retired policy." }
  }
}
$destIds = @()
if (Test-Path $destPath) { $destIds = @(([System.IO.File]::ReadAllText($destPath) | ConvertFrom-Json) | ForEach-Object { $_.id }) }
$actIds = @()
if (Test-Path $actPath) { $actIds = @(([System.IO.File]::ReadAllText($actPath) | ConvertFrom-Json) | ForEach-Object { $_.id }) }
$hotelIds = @()
if (Test-Path $hotelDir) { $hotelIds = @(Get-ChildItem $hotelDir -Filter '*.json' | ForEach-Object { ([System.IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json).id }) }

$dupes = $tours | Group-Object id | Where-Object Count -gt 1
foreach ($d in $dupes) { $errors += "Duplicate tour id: $($d.Name)" }
foreach ($t in $tours) {
  if (-not $t.id -or -not $t.name -or -not $t.page_file) { $errors += "$($t.__file): missing id, name, or page_file"; continue }
  if ($t.id -notmatch '^[a-z0-9-]+$') { $errors += "$($t.__file): invalid id '$($t.id)'" }
  $pagePath = Join-Path $root ($t.page_file -replace '/', '\')
  if (-not (Test-Path $pagePath)) { $errors += "$($t.__file): missing tour page '$($t.page_file)'" }
  if ($t.hero_image) {
    $imgPath = Join-Path $root ($t.hero_image -replace '/', '\')
    if (-not (Test-Path $imgPath)) { $warnings += "$($t.__file): missing hero image '$($t.hero_image)'" }
  } else { $warnings += "$($t.__file): no hero_image assigned" }
  foreach ($id in @($t.destination_ids)) { if ($destIds -notcontains $id) { $errors += "$($t.__file): unknown destination '$id'" } }
  foreach ($id in @($t.activity_ids)) { if ($actIds -notcontains $id) { $errors += "$($t.__file): unknown activity '$id'" } }
  foreach ($id in @($t.featured_hotel_ids)) { if ($hotelIds.Count -gt 0 -and $hotelIds -notcontains $id) { $errors += "$($t.__file): unknown hotel '$id'" } }
  if (-not $t.short_description) { $warnings += "$($t.__file): missing short_description" }
  if (@($t.activity_ids).Count -eq 0) { $warnings += "$($t.__file): no activities assigned" }
  if (-not $t.duration_label) { $warnings += "$($t.__file): duration_label pending editorial review" }
}

$report = @()
$report += 'Wild Engine - Tour Knowledge Graph Report'
$report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$report += "Tours: $($tours.Count)"
$report += "Errors: $($errors.Count)"
$report += "Warnings: $($warnings.Count)"
$report += ''
if ($errors.Count) { $report += 'ERRORS'; $report += ($errors | ForEach-Object { "- $_" }); $report += '' }
if ($warnings.Count) { $report += 'WARNINGS'; $report += ($warnings | ForEach-Object { "- $_" }); $report += '' }
$reportPath = Join-Path $root 'tour-knowledge-report.txt'
[System.IO.File]::WriteAllLines($reportPath, $report, [System.Text.UTF8Encoding]::new($false))
if ($errors.Count -gt 0) {
  Write-Host 'Tour Knowledge Graph validation failed.' -ForegroundColor Red
  Write-Host "Tours: $($tours.Count) | Errors: $($errors.Count) | Warnings: $($warnings.Count)"
  Write-Host 'Report: tour-knowledge-report.txt'
  exit 1
}
Write-Host 'Tour Knowledge Graph validation passed.' -ForegroundColor Green
Write-Host "Tours: $($tours.Count) | Warnings: $($warnings.Count)"
Write-Host 'Report: tour-knowledge-report.txt'

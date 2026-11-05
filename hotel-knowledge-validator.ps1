# Wild Papagayo - Hotel Knowledge Graph Validator v1.0
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$hotelDir = Join-Path $root 'knowledge\hotels'
$airportPath = Join-Path $root 'knowledge\airports.json'
$tourPath = Join-Path $root 'knowledge\tours.json'
$blogPath = Join-Path $root 'blog-data.json'
$destinationDir = Join-Path $root 'knowledge\destinations'
$reportPath = Join-Path $root 'hotel-knowledge-report.txt'

$errors = New-Object System.Collections.ArrayList
$warnings = New-Object System.Collections.ArrayList

function Add-ErrorLine([string]$Text) { [void]$errors.Add($Text) }
function Add-WarningLine([string]$Text) { [void]$warnings.Add($Text) }

if (-not (Test-Path $hotelDir)) { Add-ErrorLine 'Missing knowledge/hotels directory.' }

$airports = @()
$tours = @()
$blogs = @()
if (Test-Path $airportPath) { $airports = @((Get-Content $airportPath -Raw | ConvertFrom-Json)) }
if (Test-Path $tourPath) { $tours = @((Get-Content $tourPath -Raw | ConvertFrom-Json)) }
if (Test-Path $blogPath) { $blogs = @((Get-Content $blogPath -Raw | ConvertFrom-Json)) }

$airportIds = @($airports | ForEach-Object { $_.id })
$tourIds = @($tours | ForEach-Object { $_.id })
$blogSlugs = @($blogs | ForEach-Object { $_.slug })
$destinationIds = @()
if (Test-Path $destinationDir) {
  $destinationIds = @(Get-ChildItem $destinationDir -Filter '*.json' | ForEach-Object { (Get-Content $_.FullName -Raw | ConvertFrom-Json).id })
}

$hotelFiles = @(Get-ChildItem $hotelDir -Filter '*.json' -ErrorAction SilentlyContinue)
$seenIds = @{}
foreach ($file in $hotelFiles) {
  try { $h = Get-Content $file.FullName -Raw | ConvertFrom-Json }
  catch { Add-ErrorLine "$($file.Name): invalid JSON - $($_.Exception.Message)"; continue }

  foreach ($field in @('id','name','slug','brand','category','destination_id','airport_id','description','status')) {
    if (-not $h.$field) { Add-ErrorLine "$($file.Name): missing required field '$field'" }
  }
  if ($h.id) {
    if ($seenIds.ContainsKey([string]$h.id)) { Add-ErrorLine "$($file.Name): duplicate hotel id '$($h.id)'" }
    else { $seenIds[[string]$h.id] = $true }
  }
  if ($h.slug -and $h.id -and $h.slug -ne $h.id) { Add-WarningLine "$($file.Name): slug '$($h.slug)' differs from id '$($h.id)'" }
  if ($h.destination_id -and ($destinationIds -notcontains $h.destination_id)) { Add-ErrorLine "$($file.Name): destination '$($h.destination_id)' does not exist" }
  if ($h.airport_id -and ($airportIds -notcontains $h.airport_id)) { Add-ErrorLine "$($file.Name): airport '$($h.airport_id)' does not exist" }
  foreach ($tourId in @($h.featured_tours)) {
    if ($tourIds -notcontains $tourId) { Add-ErrorLine "$($file.Name): tour '$tourId' does not exist" }
  }
  foreach ($slug in @($h.related_articles)) {
    if ($blogSlugs -notcontains $slug) { Add-WarningLine "$($file.Name): related article '$slug' does not exist yet" }
  }
  foreach ($dest in @($h.nearby_destinations)) {
    if ($destinationIds -notcontains $dest) { Add-WarningLine "$($file.Name): nearby destination '$dest' does not exist" }
  }
  if (-not $h.hero_image) { Add-WarningLine "$($file.Name): hero_image is empty; add an approved hotel image before publishing" }
  elseif (-not (Test-Path (Join-Path $root $h.hero_image))) { Add-WarningLine "$($file.Name): hero image '$($h.hero_image)' was not found" }
  if ($h.status -eq 'published' -and -not $h.hero_image) { Add-ErrorLine "$($file.Name): a published hotel must have a hero_image" }

  # factual_attributes is optional on every hotel; these checks run ONLY when the
  # field is present, and never make it mandatory for hotels that don't have it yet.
  if ($h.factual_attributes) {
    $fa = $h.factual_attributes
    if ($null -ne $fa.adults_only -and $fa.adults_only -isnot [bool]) {
      Add-ErrorLine "$($file.Name): factual_attributes.adults_only must be a boolean"
    }
    $allowedAllInclusive = @('ALL_INCLUSIVE','OPTIONAL_PACKAGE','NOT_ALL_INCLUSIVE')
    if ($fa.all_inclusive_type -and ($allowedAllInclusive -notcontains $fa.all_inclusive_type)) {
      Add-ErrorLine "$($file.Name): factual_attributes.all_inclusive_type '$($fa.all_inclusive_type)' is not an approved value"
    }
    if ($fa.beach_relationship -and $fa.beach_relationship -ne 'NOT_APPLICABLE') {
      $br = $fa.beach_relationship
      foreach ($key in @($br.PSObject.Properties.Name)) {
        if (@('beachfront','direct_access','proximity_note') -notcontains $key) {
          Add-ErrorLine "$($file.Name): factual_attributes.beach_relationship has unapproved key '$key'"
        }
      }
    }
    if ($null -ne $fa.on_property_dining_count -and ([int]$fa.on_property_dining_count -lt 0)) {
      Add-ErrorLine "$($file.Name): factual_attributes.on_property_dining_count must be >= 0"
    }
    $sourceIds = @()
    if ($fa.evidence_sources) { $sourceIds = @($fa.evidence_sources.PSObject.Properties.Name) }
    # family_facts is optional and presence-only: V1 keys may only ever be `true` (never
    # `false`, which would wrongly imply confirmed absence instead of "not established").
    # Each present key requires its own fact_evidence["family_facts.<key>"] entry -- more
    # granular than beach_relationship's shared entry, by deliberate owner decision, so a
    # future property can cite a different source per family fact.
    $allowedFamilyFacts = @('family_rooms_available','childrens_programming_available')
    if ($fa.family_facts) {
      $ff = $fa.family_facts
      foreach ($key in @($ff.PSObject.Properties.Name)) {
        if ($allowedFamilyFacts -notcontains $key) {
          Add-ErrorLine "$($file.Name): family_facts has unapproved key '$key'"
        } elseif ($ff.$key -isnot [bool] -or $ff.$key -ne $true) {
          Add-ErrorLine "$($file.Name): family_facts.$key must be true (presence-only; do not write false)"
        } else {
          $evKey = "family_facts.$key"
          $hasEvidence = $fa.fact_evidence -and $fa.fact_evidence.PSObject.Properties[$evKey] -and @($fa.fact_evidence.$evKey).Count -gt 0
          if (-not $hasEvidence) {
            Add-ErrorLine "$($file.Name): family_facts.$key is present but missing fact_evidence['$evKey']"
          }
        }
      }
    }
    $allowedAudience = @('HONEYMOON','COUPLES','ROMANCE','ANNIVERSARY','WEDDING','FAMILY')
    $allowedEvidenceType = @('EXPLICIT_MARKETING','DEDICATED_PAGE','TREATMENT_OFFERING','GENERIC_MENTION','PAGE_EXISTENCE_ONLY')
    $allowedScope = @('PROPERTY_LEVEL','PAGE_LEVEL','PACKAGE_LEVEL','TREATMENT_LEVEL','RESIDENCE_LEVEL')
    if ($null -ne $fa.positioning_evidence) {
      foreach ($pe in @($fa.positioning_evidence)) {
        if ($allowedAudience -notcontains $pe.audience) { Add-ErrorLine "$($file.Name): positioning_evidence has unapproved audience '$($pe.audience)'" }
        if ($allowedEvidenceType -notcontains $pe.evidence_type) { Add-ErrorLine "$($file.Name): positioning_evidence has unapproved evidence_type '$($pe.evidence_type)'" }
        if ($allowedScope -notcontains $pe.scope) { Add-ErrorLine "$($file.Name): positioning_evidence has unapproved scope '$($pe.scope)'" }
        if ($pe.source_id -and ($sourceIds -notcontains $pe.source_id)) { Add-ErrorLine "$($file.Name): positioning_evidence.source_id '$($pe.source_id)' does not exist in evidence_sources" }
      }
    }
    if ($fa.fact_evidence) {
      foreach ($fieldName in @($fa.fact_evidence.PSObject.Properties.Name)) {
        foreach ($srcId in @($fa.fact_evidence.$fieldName)) {
          if ($sourceIds -notcontains $srcId) { Add-ErrorLine "$($file.Name): fact_evidence.$fieldName references unknown source_id '$srcId'" }
        }
      }
      # Backward half of family_facts' bidirectional provenance: a fact_evidence["family_facts.<key>"]
      # entry must not exist unless that exact key is also present (true) in family_facts itself.
      foreach ($familyEvKey in @($fa.fact_evidence.PSObject.Properties.Name | Where-Object { $_ -like 'family_facts.*' })) {
        $factKey = $familyEvKey -replace '^family_facts\.', ''
        $factPresent = $fa.family_facts -and $fa.family_facts.PSObject.Properties[$factKey] -and $fa.family_facts.$factKey -eq $true
        if (-not $factPresent) {
          Add-ErrorLine "$($file.Name): fact_evidence['$familyEvKey'] exists but family_facts.$factKey is not present"
        }
      }
    }
  }
}

$lines = New-Object System.Collections.ArrayList
[void]$lines.Add('Wild Engine - Hotel Knowledge Graph Report')
[void]$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$lines.Add("Hotels: $($hotelFiles.Count)")
[void]$lines.Add("Errors: $($errors.Count)")
[void]$lines.Add("Warnings: $($warnings.Count)")
[void]$lines.Add('')
if ($errors.Count -gt 0) {
  [void]$lines.Add('ERRORS')
  foreach ($e in $errors) { [void]$lines.Add("- $e") }
  [void]$lines.Add('')
}
if ($warnings.Count -gt 0) {
  [void]$lines.Add('WARNINGS')
  foreach ($w in $warnings) { [void]$lines.Add("- $w") }
  [void]$lines.Add('')
}
[void]$lines.Add($(if ($errors.Count -eq 0) { 'Validation passed.' } else { 'Validation failed.' }))
[System.IO.File]::WriteAllLines($reportPath, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))

if ($errors.Count -eq 0) {
  Write-Host 'Hotel Knowledge Graph validation passed.' -ForegroundColor Green
  Write-Host "Hotels: $($hotelFiles.Count) | Warnings: $($warnings.Count)"
  Write-Host 'Report: hotel-knowledge-report.txt'
  exit 0
}
Write-Host "Hotel Knowledge Graph validation failed with $($errors.Count) error(s)." -ForegroundColor Red
Write-Host 'Report: hotel-knowledge-report.txt'
exit 1

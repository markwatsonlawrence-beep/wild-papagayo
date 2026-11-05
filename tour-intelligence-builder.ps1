param(
    [string]$TourId,
    [switch]$All,
    [switch]$Force,
    [switch]$NoBackup,
    [string[]]$ScoreTourIds,
    [switch]$WriteScores
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$toursDir = Join-Path $root "knowledge\tours"
$backupRoot = Join-Path $root "knowledge\backups\tours-intelligence"

if (-not (Test-Path $toursDir)) {
    throw "Tours directory not found: $toursDir"
}

function Get-PropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function Set-OrAddProperty {
    param($Object, [string]$Name, $Value)
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { $prop.Value = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Normalize-Text {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    # Construye los caracteres daÃ±ados por cÃ³digo Unicode,
    # evitando problemas de codificaciÃ³n dentro del archivo PS1.
    $badEmDash     = ([string][char]0x00E2) + ([char]0x20AC) + ([char]0x201D)
    $badEnDash     = ([string][char]0x00E2) + ([char]0x20AC) + ([char]0x201C)
    $badApostrophe = ([string][char]0x00E2) + ([char]0x20AC) + ([char]0x2122)

    $Text = $Text.Replace($badEmDash,     [string][char]0x2014)
    $Text = $Text.Replace($badEnDash,     [string][char]0x2013)
    $Text = $Text.Replace($badApostrophe, [string][char]0x2019)

    return $Text
}

function Get-DurationHours {
    param([string]$DurationLabel)
    if ([string]::IsNullOrWhiteSpace($DurationLabel)) { return 8 }
    $match = [regex]::Match($DurationLabel, '(\d+(?:\.\d+)?)\s*hours?', 'IgnoreCase')
    if ($match.Success) { return [double]$match.Groups[1].Value }
    if ($DurationLabel -match 'Half Day') { return 5 }
    if ($DurationLabel -match 'Full Day') { return 9 }
    return 8
}

# ---- Formula v2.1: traveler_scores only (frozen spec) ----
# Additive, opt-in mode. Never invoked by -All/-TourId/-Force (the existing
# full-profile rebuild path above is untouched). Writes ONLY the 5 scored
# dimensions inside intelligence.traveler_scores; couples/private and every
# other field are preserved exactly as read.

$Script:HighAdventureActivities = @('atv','ziplining','rafting','tubing','horseback-riding','hiking','hanging-bridges')
$Script:WildlifeSpeciesActivities = @('sloth-watching','turtle-watching')
$Script:WildlifeGenericActivities = @('wildlife-watching')

function Get-ScoreBand {
    param([double]$Value)
    $clamped = [Math]::Max(0, [Math]::Min(100, $Value))
    $bands = @(0,25,50,75,100)
    $best = $bands[0]
    $bestDiff = [Math]::Abs($bands[0] - $clamped)
    foreach ($b in $bands) {
        $diff = [Math]::Abs($b - $clamped)
        if ($diff -lt $bestDiff) { $best = $b; $bestDiff = $diff }
    }
    return $best
}

function Get-AccordionRestrictionText {
    param($Tour)
    $pc = Get-PropertyValue $Tour "page_content" $null
    $accordion = Get-PropertyValue $pc "accordion" $null
    $gc = @((Get-PropertyValue $accordion "guest_considerations" @()))
    $bya = @((Get-PropertyValue $accordion "before_you_arrive" @()))
    $combined = @($gc) + @($bya)
    $text = ($combined -join " ") -replace '<[^>]+>', ''
    return $text
}

function Test-FamiliesRestrictionText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if ([regex]::IsMatch($Text, 'not suitable for (guests|children|anyone|those|people)', 'IgnoreCase')) { return $true }
    if ($Text.ToLowerInvariant().Contains('heart condition')) { return $true }
    return $false
}

function Test-SeniorsRestrictionText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $lower = $Text.ToLowerInvariant()
    foreach ($kw in @('knee','joint','heart condition','mobility','significant height','steep')) {
        if ($lower.Contains($kw)) { return $true }
    }
    return $false
}

function Get-TravelerScoresV21 {
    param($Tour)

    $flags = New-Object System.Collections.Generic.List[string]

    $activityIds = @((Get-PropertyValue $Tour "activity_ids" @()))
    $minimumAge = Get-PropertyValue $Tour "minimum_age" $null
    $difficulty = [string](Get-PropertyValue $Tour "difficulty" "")
    $itineraryBlock = Get-PropertyValue $Tour "itinerary" $null
    $intensity = [string](Get-PropertyValue $itineraryBlock "intensity" "")
    $intel = Get-PropertyValue $Tour "intelligence" $null
    $energyLevel = [string](Get-PropertyValue $intel "energy_level" "")
    $durationHours = Get-PropertyValue $intel "duration_hours" $null
    $primaryCategory = [string](Get-PropertyValue $intel "primary_category" "")

    if ($activityIds.Count -eq 0) { $flags.Add("empty activity_ids") | Out-Null }
    if ($null -eq $minimumAge) { $flags.Add("missing minimum_age") | Out-Null }
    if ([string]::IsNullOrWhiteSpace($difficulty)) { $flags.Add("missing difficulty") | Out-Null }
    if ([string]::IsNullOrWhiteSpace($intensity) -and [string]::IsNullOrWhiteSpace($energyLevel)) {
        $flags.Add("missing intensity AND energy_level") | Out-Null
    }

    # Resolve an intensity-equivalent key for the bonus/base tables.
    if (-not [string]::IsNullOrWhiteSpace($intensity)) {
        $intensityKey = $intensity.ToLowerInvariant()
    } elseif ($energyLevel -eq "High") { $intensityKey = "heavy" }
    elseif ($energyLevel -eq "Low") { $intensityKey = "light" }
    elseif (-not [string]::IsNullOrWhiteSpace($energyLevel)) { $intensityKey = "moderate" }
    else { $intensityKey = "moderate" }

    # ---- ADVENTURE ----
    $nAdv = @($activityIds | Where-Object { $Script:HighAdventureActivities -contains $_ }).Count
    $advBase = switch ($nAdv) { 0 {0} 1 {25} 2 {50} default {75} }
    $advBonus = switch ($intensityKey) { "heavy" {50} "light" {0} default {25} }
    $adventureRaw = $advBase + $advBonus
    if ($nAdv -eq 0 -and $difficulty -eq "Easy") { $adventureRaw = 0 }
    $adventure = Get-ScoreBand $adventureRaw

    # ---- WILDLIFE ----
    $nSpecies = @($activityIds | Where-Object { $Script:WildlifeSpeciesActivities -contains $_ }).Count
    $nGeneric = @($activityIds | Where-Object { $Script:WildlifeGenericActivities -contains $_ }).Count
    $weighted = ($nSpecies * 2) + ($nGeneric * 1)
    $wildlife = switch ($weighted) { 0 {0} 1 {50} 2 {75} default {100} }
    if ($primaryCategory -eq "Nature & Wildlife" -and $weighted -eq 0) {
        $flags.Add("category=Nature & Wildlife but 0 wildlife activities") | Out-Null
    }
    if ($weighted -ge 2 -and $primaryCategory -ne "Nature & Wildlife") {
        $flags.Add("strong wildlife activities but category != Nature & Wildlife") | Out-Null
    }

    $restrictionText = Get-AccordionRestrictionText $Tour

    # ---- FAMILIES ----
    if ($null -eq $minimumAge) { $famBase = 50 }
    elseif ($minimumAge -eq 0) { $famBase = 100 }
    elseif ($minimumAge -ge 1 -and $minimumAge -le 5) { $famBase = 75 }
    elseif ($minimumAge -ge 6 -and $minimumAge -le 9) { $famBase = 50 }
    else { $famBase = 25 }
    $famPenalty = 0
    if ($intensityKey -eq "heavy") { $famPenalty += 25 }
    if ($null -ne $durationHours -and [double]$durationHours -gt 10) { $famPenalty += 25 }
    if (Test-FamiliesRestrictionText $restrictionText) { $famPenalty += 25 }
    $families = Get-ScoreBand ($famBase - $famPenalty)

    # ---- SENIORS ----
    switch ($difficulty) {
        "Easy" { $seniorBase = 100 }
        "Easy to Moderate" { $seniorBase = 75 }
        "Moderate" { $seniorBase = 50 }
        default { $seniorBase = $(if ([string]::IsNullOrWhiteSpace($difficulty)) { 50 } else { 25 }) }
    }
    $seniorPenalty = 0
    if ($null -ne $durationHours -and [double]$durationHours -gt 10) { $seniorPenalty += 25 }
    if (Test-SeniorsRestrictionText $restrictionText) { $seniorPenalty += 25 }
    if ($activityIds -contains "night-tour") { $seniorPenalty += 25 }
    $seniors = Get-ScoreBand ($seniorBase - $seniorPenalty)

    # ---- RELAXATION ----
    $relaxBase = switch ($intensityKey) { "light" {75} "heavy" {25} default {50} }
    $relaxBonus = 0
    if ($activityIds -contains "hot-springs") { $relaxBonus += 25 }
    if ($activityIds -contains "boat-tour") { $relaxBonus += 25 }
    $relaxPenalty = $(if ($null -ne $durationHours -and [double]$durationHours -gt 10) { 25 } else { 0 })
    $relaxation = Get-ScoreBand ($relaxBase + $relaxBonus - $relaxPenalty)

    return [pscustomobject]@{
        families=$families
        seniors=$seniors
        adventure=$adventure
        wildlife=$wildlife
        relaxation=$relaxation
        flags=@($flags)
    }
}

function Get-PrimaryCategory {
    param($Tour)
    $name = ([string](Get-PropertyValue $Tour "name" "")).ToLowerInvariant()
    $category = ([string](Get-PropertyValue $Tour "category" "")).ToLowerInvariant()
    $activities = @((Get-PropertyValue $Tour "activity_ids" @())) -join " "
    $haystack = "$name $category $activities"
    if ($haystack -match 'catamaran|sail|snorkel|ocean|sunset') { return "Ocean" }
    if ($haystack -match 'rafting|tubing|canyoning|river') { return "Water Adventure" }
    if ($haystack -match 'atv|zipline|canopy|adventure park') { return "Adventure" }
    if ($haystack -match 'volcano|hot spring|thermal|rincon|miravalles|arenal') { return "Volcano & Wellness" }
    if ($haystack -match 'sloth|wildlife|bird|nature|hanging bridge|rainforest') { return "Nature & Wildlife" }
    if ($haystack -match 'coffee|chocolate|culture|hacienda|farm') { return "Culture & Local Life" }
    if ($haystack -match 'waterfall|celeste|la leona') { return "Waterfalls & Nature" }
    return "General Experience"
}

function Get-EnergyLevel {
    param([string]$Category, [string]$Difficulty, [double]$DurationHours)
    $difficultyText = ([string]$Difficulty).ToLowerInvariant()
    if ($difficultyText -match 'hard|difficult|challenging') { return "High" }
    if ($Category -in @("Adventure", "Water Adventure")) { return "High" }
    if ($Category -eq "Ocean") { return "Low" }
    if ($Category -eq "Volcano & Wellness") { return "Medium" }
    if ($DurationHours -ge 9) { return "Medium" }
    return "Medium"
}

function Get-Difficulty {
    param($Tour, [string]$Category)
    $existing = [string](Get-PropertyValue $Tour "difficulty" "")
    if (-not [string]::IsNullOrWhiteSpace($existing)) { return $existing }
    switch ($Category) {
        "Adventure" { return "Moderate" }
        "Water Adventure" { return "Moderate" }
        "Ocean" { return "Easy" }
        "Nature & Wildlife" { return "Easy" }
        "Volcano & Wellness" { return "Easy to Moderate" }
        "Waterfalls & Nature" { return "Moderate" }
        default { return "Easy" }
    }
}

function Get-DefaultBestFor {
    param([string]$Category)
    switch ($Category) {
        "Nature & Wildlife" { return @("Families", "Couples", "Nature lovers", "First-time visitors") }
        "Ocean" { return @("Couples", "Families", "Relaxed travelers", "Sunset seekers") }
        "Adventure" { return @("Adventure travelers", "Friends", "Active couples") }
        "Water Adventure" { return @("Adventure travelers", "Teens", "Active groups") }
        "Volcano & Wellness" { return @("Couples", "Wellness travelers", "Nature lovers") }
        "Culture & Local Life" { return @("Families", "Culture lovers", "Curious travelers") }
        "Waterfalls & Nature" { return @("Couples", "Families", "Nature lovers", "Photographers") }
        default { return @("Couples", "Families", "First-time visitors") }
    }
}

function Get-ProfileScores {
    param([string]$Category, [string]$Energy)
    $scores = [ordered]@{families=80;couples=85;seniors=75;adventure=70;private=80;wildlife=65;relaxation=60}
    switch ($Category) {
        "Nature & Wildlife" {$scores.families=95;$scores.couples=90;$scores.seniors=90;$scores.adventure=65;$scores.private=85;$scores.wildlife=100;$scores.relaxation=65}
        "Ocean" {$scores.families=90;$scores.couples=95;$scores.seniors=85;$scores.adventure=55;$scores.private=95;$scores.wildlife=60;$scores.relaxation=95}
        "Adventure" {$scores.families=70;$scores.couples=85;$scores.seniors=45;$scores.adventure=100;$scores.private=75;$scores.wildlife=45;$scores.relaxation=25}
        "Water Adventure" {$scores.families=65;$scores.couples=80;$scores.seniors=35;$scores.adventure=100;$scores.private=70;$scores.wildlife=50;$scores.relaxation=20}
        "Volcano & Wellness" {$scores.families=85;$scores.couples=95;$scores.seniors=80;$scores.adventure=65;$scores.private=90;$scores.wildlife=65;$scores.relaxation=90}
        "Culture & Local Life" {$scores.families=90;$scores.couples=80;$scores.seniors=90;$scores.adventure=35;$scores.private=75;$scores.wildlife=40;$scores.relaxation=70}
        "Waterfalls & Nature" {$scores.families=80;$scores.couples=90;$scores.seniors=60;$scores.adventure=80;$scores.private=80;$scores.wildlife=70;$scores.relaxation=55}
    }
    if ($Energy -eq "High") {$scores.seniors=[Math]::Min($scores.seniors,55);$scores.relaxation=[Math]::Min($scores.relaxation,40)}
    return [pscustomobject]$scores
}

function Get-SequenceRules {
    param([string]$Category, [string]$Energy)
    $idealAfter = @("arrival", "rest", "beach")
    $avoidAfter = @()
    if ($Energy -eq "High") { $avoidAfter = @("adventure", "full-day") }
    elseif ($Category -eq "Ocean") { $idealAfter = @("adventure", "full-day", "rest") }
    elseif ($Category -eq "Volcano & Wellness") { $idealAfter = @("arrival", "rest") }
    return [pscustomobject]@{ideal_after=$idealAfter;avoid_after=$avoidAfter;recovery_day_recommended=($Energy -eq "High")}
}

function Get-TourPriority {
    param($Tour, [string]$Category)
    $featuredHotels = @((Get-PropertyValue $Tour "featured_hotel_ids" @())).Count
    $pricing = Get-PropertyValue $Tour "pricing" $null
    $hasPrice = $null -ne (Get-PropertyValue $pricing "from_price" $null)
    $active = ([string](Get-PropertyValue $Tour "status" "active")) -eq "active"
    $score = 70
    if ($featuredHotels -gt 0) { $score += [Math]::Min(15, $featuredHotels * 5) }
    if ($hasPrice) { $score += 5 }
    if ($active) { $score += 5 }
    if ($Category -in @("Nature & Wildlife", "Volcano & Wellness", "Ocean")) { $score += 5 }
    return [Math]::Min(100, $score)
}

function New-IntelligenceProfile {
    param($Tour)
    $durationLabel = [string](Get-PropertyValue $Tour "duration_label" "")
    $durationHours = Get-DurationHours $durationLabel
    $category = Get-PrimaryCategory $Tour
    $difficulty = Get-Difficulty $Tour $category
    $energy = Get-EnergyLevel $category $difficulty $durationHours
    $bestFor = @((Get-PropertyValue $Tour "best_for" @()))
    if ($bestFor.Count -eq 0) { $bestFor = Get-DefaultBestFor $category }
    $sequence = Get-SequenceRules $category $energy
    $scores = Get-ProfileScores $category $energy
    $priority = Get-TourPriority $Tour $category
    $minimumAge = Get-PropertyValue $Tour "minimum_age" $null
    if ($null -eq $minimumAge) { if ($energy -eq "High") { $minimumAge = 8 } else { $minimumAge = 0 } }
    $activityIds = @((Get-PropertyValue $Tour "activity_ids" @()))
    $pickupZones = @((Get-PropertyValue $Tour "pickup_zone_ids" @()))

    if ($pickupZones.Count -eq 0) {
        $itineraryBlock = Get-PropertyValue $Tour "itinerary" $null
        if ($null -ne $itineraryBlock) {
            $pickupZones = @((Get-PropertyValue $itineraryBlock "pickup_zones" @()))
        }
    }

    if (@((Get-PropertyValue $Tour "pickup_zone_ids" @())).Count -eq 0 -and $pickupZones.Count -gt 0) {
        Set-OrAddProperty $Tour "pickup_zone_ids" @($pickupZones)
    }

    $seasons = @((Get-PropertyValue $Tour "season_ids" @("all-year")))

    return [pscustomobject][ordered]@{
        schema_version="2.0"
        intelligence_status="auto_generated_review_required"
        primary_category=$category
        difficulty=$difficulty
        duration_hours=$durationHours
        duration_type=$(if($durationHours -le 5){"Half Day"}elseif($durationHours -ge 8){"Full Day"}else{"Extended Half Day"})
        energy_level=$energy
        minimum_age=$minimumAge
        best_for=$bestFor
        traveler_scores=$scores
        pickup_zone_ids=$pickupZones
        season_ids=$seasons
        activity_tags=$activityIds
        itinerary_rules=$sequence
        stay_fit=[pscustomobject]@{
            minimum_nights=$(if($durationHours -ge 8){4}else{3})
            ideal_nights=$(if($energy -eq "High"){@(5,7,10)}else{@(4,7,10,14)})
            preferred_trip_day=$(if($energy -eq "High"){@(2,4,6)}else{@(2,3,5,6)})
        }
        recommendation_priority=$priority
        balance_tags=@($(if($energy -eq "High"){"adventure"}else{"balanced"}),$category.ToLowerInvariant().Replace(" & ","-").Replace(" ","-"))
        editorial_review=[pscustomobject]@{
            required=$true
            notes=@("Verify pickup zones.","Verify minimum age and difficulty.","Review traveler scores before public use.")
        }
        last_generated=(Get-Date).ToString("yyyy-MM-dd")
    }
}

# ---- Formula v2.1 scores-only mode ----
# Requires explicit -ScoreTourIds (never defaults to the full catalog).
# Without -WriteScores this is a pure dry-run/report; nothing is written
# unless -WriteScores is also passed.
if ($ScoreTourIds -and $ScoreTourIds.Count -gt 0) {
    Write-Host ""
    Write-Host "Traveler Scores Formula v2.1 -- $(if ($WriteScores) { 'WRITE MODE' } else { 'DRY-RUN MODE (no files will be modified)' })" -ForegroundColor Cyan
    Write-Host ""
    foreach ($id in $ScoreTourIds) {
        $path = Join-Path $toursDir "$id.json"
        if (-not (Test-Path $path)) {
            Write-Host "SKIP $id -- tour file not found: $path" -ForegroundColor Red
            continue
        }
        $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        $tour = $raw | ConvertFrom-Json
        $result = Get-TravelerScoresV21 $tour

        $flagText = if ($result.flags.Count -gt 0) { " | FLAGS: " + ($result.flags -join "; ") } else { "" }
        Write-Host ("{0,-30} F:{1,-4} S:{2,-4} A:{3,-4} W:{4,-4} R:{5,-4}{6}" -f $tour.id, $result.families, $result.seniors, $result.adventure, $result.wildlife, $result.relaxation, $flagText)

        if ($WriteScores) {
            $intel = Get-PropertyValue $tour "intelligence" $null
            if ($null -eq $intel) {
                Write-Host "  SKIP WRITE $($tour.id): no existing intelligence block (this mode never creates one)" -ForegroundColor Red
                continue
            }
            $existingScores = Get-PropertyValue $intel "traveler_scores" $null
            if ($null -eq $existingScores) {
                Write-Host "  SKIP WRITE $($tour.id): no existing traveler_scores block" -ForegroundColor Red
                continue
            }

            # Surgical raw-text replacement of ONLY the 5 scored fields inside the
            # traveler_scores block. Deliberately avoids ConvertTo-Json on the whole
            # object, which would re-serialize (and silently reformat/re-indent)
            # every other field in the file. couples/private and everything else
            # stay byte-identical.
            $blockMatch = [regex]::Match($raw, '"traveler_scores":\s*\{(?<inner>.*?)\}', 'Singleline')
            if (-not $blockMatch.Success) {
                Write-Host "  SKIP WRITE $($tour.id): could not locate traveler_scores block in raw text" -ForegroundColor Red
                continue
            }
            $inner = $blockMatch.Groups['inner'].Value
            $newInner = $inner
            $fieldMap = [ordered]@{
                'families'=$result.families; 'seniors'=$result.seniors
                'adventure'=$result.adventure; 'wildlife'=$result.wildlife
                'relaxation'=$result.relaxation
            }
            $missingField = $false
            foreach ($fieldName in $fieldMap.Keys) {
                $fieldRe = [regex]::Match($newInner, "(""$fieldName"":\s*)\d+")
                if (-not $fieldRe.Success) {
                    Write-Host "  SKIP WRITE $($tour.id): field '$fieldName' not found in traveler_scores block" -ForegroundColor Red
                    $missingField = $true
                    break
                }
                $newInner = $newInner -replace "(""$fieldName"":\s*)\d+", "`${1}$($fieldMap[$fieldName])"
            }
            if ($missingField) { continue }

            $newBlock = '"traveler_scores":' + $blockMatch.Value.Substring('"traveler_scores":'.Length, $blockMatch.Value.IndexOf('{') - '"traveler_scores":'.Length) + '{' + $newInner + '}'
            $newRaw = $raw.Substring(0, $blockMatch.Index) + $newBlock + $raw.Substring($blockMatch.Index + $blockMatch.Length)

            if ($newRaw -eq $raw) {
                Write-Host "  NOTE $($tour.id): computed scores identical to existing values, no change written" -ForegroundColor DarkGray
            }

            if (-not $NoBackup) {
                $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $backupDir = Join-Path $backupRoot "$stamp-scores-only"
                New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
                Copy-Item $path (Join-Path $backupDir "$id.json")
            }
            [System.IO.File]::WriteAllText($path, $newRaw, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "  WRITTEN $($tour.id)" -ForegroundColor Green
        }
    }
    Write-Host ""
    exit 0
}

$files = @()
if ($All) {
    $files = @(Get-ChildItem -Path $toursDir -Filter "*.json" -File | Sort-Object Name)
}
elseif (-not [string]::IsNullOrWhiteSpace($TourId)) {
    $path = Join-Path $toursDir "$TourId.json"
    if (-not (Test-Path $path)) { throw "Tour file not found: $path" }
    $files = @(Get-Item $path)
}
else {
    throw "Use -All or -TourId <id>."
}

if (-not $NoBackup) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $backupRoot $stamp
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    foreach ($file in $files) { Copy-Item $file.FullName (Join-Path $backupDir $file.Name) }
    Write-Host "Backup created: $backupDir" -ForegroundColor DarkGray
}

$updated = 0
$skipped = 0
foreach ($file in $files) {
    $raw = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $tour = $raw | ConvertFrom-Json
    $existing = Get-PropertyValue $tour "intelligence" $null
    if ($null -ne $existing -and -not $Force) {
        Write-Host "SKIP $($tour.id): intelligence already exists" -ForegroundColor Yellow
        $skipped++
        continue
    }
    $shortDescription = [string](Get-PropertyValue $tour "short_description" "")
    if (-not [string]::IsNullOrWhiteSpace($shortDescription)) { Set-OrAddProperty $tour "short_description" (Normalize-Text $shortDescription) }
    $tourProfile = New-IntelligenceProfile $tour
    Set-OrAddProperty $tour "intelligence" $tourProfile
    if (@((Get-PropertyValue $tour "best_for" @())).Count -eq 0) { Set-OrAddProperty $tour "best_for" @($tourProfile.best_for) }
    if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue $tour "difficulty" ""))) { Set-OrAddProperty $tour "difficulty" $tourProfile.difficulty }
    if ($null -eq (Get-PropertyValue $tour "minimum_age" $null)) { Set-OrAddProperty $tour "minimum_age" $tourProfile.minimum_age }
    $json = $tour | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($file.FullName,$json,(New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("UPDATED {0} | {1} | {2} | priority {3}" -f $tour.id,$tourProfile.primary_category,$tourProfile.energy_level,$tourProfile.recommendation_priority) -ForegroundColor Green
    $updated++
}

Write-Host ""
Write-Host "Tour Intelligence Builder complete." -ForegroundColor Cyan
Write-Host "Updated: $updated | Skipped: $skipped | Total: $($files.Count)"
Write-Host "Review auto-generated values before using them publicly." -ForegroundColor Yellow

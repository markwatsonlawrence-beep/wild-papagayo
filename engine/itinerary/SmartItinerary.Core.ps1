# WEP 2.1 - Smart Itinerary Engine Core
# Generates hotel-specific suggested_stay sequences from tour intelligence profiles.
# PS5.1 compatible. No I/O - pure algorithm functions only.

# ── Safe property access ──────────────────────────────────────────────────────

function _SIP_GetStr {
    param($Obj, [string]$Key, [string]$Default = "")
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Key]
    if ($null -ne $p -and $null -ne $p.Value) { return [string]$p.Value }
    return $Default
}

function _SIP_GetInt {
    param($Obj, [string]$Key, [int]$Default = 0)
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Key]
    if ($null -ne $p -and $null -ne $p.Value) { return [int]$p.Value }
    return $Default
}

function _SIP_GetArr {
    param($Obj, [string]$Key)
    if ($null -eq $Obj) { return @() }
    $p = $Obj.PSObject.Properties[$Key]
    if ($null -ne $p -and $null -ne $p.Value) { return @($p.Value) }
    return @()
}

# ── Tour profile access ───────────────────────────────────────────────────────
# Tours carry two complementary blocks:
#   itinerary  - scheduling data: category, intensity, pickup_zones, min/max_stay (from tour-profile-enricher.ps1)
#   intelligence - editorial data: recommendation_priority, traveler_scores, best_for (from tour-intelligence-builder.ps1)
# The engine uses itinerary for scheduling rules and intelligence.recommendation_priority for ranking.

function Get-TourItineraryProfile {
    param($Tour)
    if ($null -eq $Tour) { return $null }
    $p = $Tour.PSObject.Properties['itinerary']
    if ($null -ne $p) { return $p.Value }
    return $null
}

function Get-TourIntelligence {
    param($Tour)
    if ($null -eq $Tour) { return $null }
    $p = $Tour.PSObject.Properties['intelligence']
    if ($null -ne $p) { return $p.Value }
    return $null
}

function Get-TourEffectiveBasePriority {
    # Prefers intelligence.recommendation_priority (dynamically computed from real data).
    # Falls back to itinerary.priority (hand-crafted baseline).
    param($Tour)
    $intel = Get-TourIntelligence $Tour
    if ($null -ne $intel) {
        $p = $intel.PSObject.Properties['recommendation_priority']
        if ($null -ne $p -and $null -ne $p.Value) { return [int]$p.Value }
    }
    $ip = Get-TourItineraryProfile $Tour
    if ($null -ne $ip) {
        $p = $ip.PSObject.Properties['priority']
        if ($null -ne $p -and $null -ne $p.Value) { return [int]$p.Value }
    }
    return 50
}

function Test-TourEligible {
    param($Tour, [string]$Zone, [int]$StayDays)
    $ip = Get-TourItineraryProfile $Tour
    if ($null -eq $ip) { return $false }

    $zones = _SIP_GetArr $ip 'pickup_zones'
    if ($zones.Count -gt 0 -and $zones -notcontains $Zone) { return $false }

    $minStay = _SIP_GetInt $ip 'min_stay' 1
    $maxStay = _SIP_GetInt $ip 'max_stay' 99
    return ($StayDays -ge $minStay -and $StayDays -le $maxStay)
}

# ── Fixed day templates ───────────────────────────────────────────────────────

function New-ArrivalDay {
    param([int]$Day)
    return [PSCustomObject]@{
        day         = $Day
        title       = "Arrival & Check-In"
        description = "Private airport transfer, check-in and a relaxed first evening at the resort."
        type        = "arrival"
    }
}

function New-ResortDay {
    param([int]$Day, [string]$HotelName)
    return [PSCustomObject]@{
        day         = $Day
        title       = "Resort & Beach Day"
        description = "Explore the resort, relax by the pool or on the beach, and recharge for the next adventure."
        type        = "resort"
    }
}

function New-FreeDayEntry {
    param([int]$Day)
    return [PSCustomObject]@{
        day         = $Day
        title       = "Free Day"
        description = "Explore the local area at your own pace or enjoy resort amenities."
        type        = "free"
    }
}

function New-DepartureDay {
    param([int]$Day, [string]$AirportId)
    $airport = switch ($AirportId.ToUpperInvariant()) {
        "LIR" { "Guanacaste Airport (LIR)" }
        "SJO" { "San Jose Airport (SJO)"   }
        default { "$AirportId Airport"      }
    }
    return [PSCustomObject]@{
        day         = $Day
        title       = "Departure"
        description = "Private transfer to $airport."
        type        = "departure"
    }
}

# ── Main algorithm ────────────────────────────────────────────────────────────

function Build-SmartItinerary {
    <#
    .SYNOPSIS
        Builds a hotel-specific suggested_stay array from tour intelligence profiles.
    .PARAMETER Hotel
        PSCustomObject: the legacy hotel JSON (needs id, name, tour_pickup_zone,
        airport_id, featured_tours).
    .PARAMETER AllTours
        Array of tour PSCustomObjects from knowledge/tours/*.json.
    .PARAMETER DurationDays
        Total trip length in days (arrival day + nights + departure day).
        Minimum 3. Default 7.
    .OUTPUTS
        Array of PSCustomObjects with: day, title, description, type [, tour_id]
    #>
    param(
        [Parameter(Mandatory=$true)] $Hotel,
        [Parameter(Mandatory=$true)] $AllTours,
        [Parameter(Mandatory=$true)] [int]$DurationDays
    )

    $zone          = _SIP_GetStr $Hotel 'tour_pickup_zone'
    $airportId     = _SIP_GetStr $Hotel 'airport_id' 'lir'
    $hotelName     = _SIP_GetStr $Hotel 'name' 'the resort'
    $featuredTours = _SIP_GetArr $Hotel 'featured_tours'

    # Resort days: 1 per 4 activity days (minimum 1 for any stay >= 4 days)
    $middleDays       = $DurationDays - 2   # minus arrival + departure
    $totalResortDays  = if ($middleDays -ge 4) { [math]::Max(1, [int][math]::Floor($middleDays / 4)) } else { 0 }
    $maxTourSlots     = $middleDays - $totalResortDays

    # ── Build eligible tour list with effective priority ───────────────────────
    # Base priority: intelligence.recommendation_priority > itinerary.priority > 50
    # Featured bonus: +20 if tour appears in hotel.featured_tours
    $eligibleWithPriority = @()
    foreach ($t in $AllTours) {
        if (-not (Test-TourEligible $t $zone $DurationDays)) { continue }
        $basePriority = Get-TourEffectiveBasePriority $t
        $isFeatured   = ($featuredTours -contains [string]$t.id)
        $bonus        = if ($isFeatured) { 20 } else { 0 }
        $t | Add-Member -NotePropertyName '_eff_priority' -NotePropertyValue ($basePriority + $bonus) -Force
        $eligibleWithPriority += $t
    }
    $eligible = @($eligibleWithPriority | Sort-Object '_eff_priority' -Descending)

    # ── Schedule ──────────────────────────────────────────────────────────────
    $result             = @()
    $scheduledIds       = @()
    $usedCategories     = @()
    $lastIntensity      = 'light'
    $consecutiveActive  = 0
    $resortDaysLeft     = $totalResortDays
    $tourSlotsLeft      = $maxTourSlots

    # Day 1: Arrival (fixed)
    $result += New-ArrivalDay 1
    $dayNum = 2

    while ($dayNum -lt $DurationDays) {
        $slotsRemaining = ($DurationDays - 1) - $dayNum   # days between today and departure

        # Insert resort day when needed:
        #   - after 2 consecutive active days
        #   - or when remaining slots <= resort days still owed (force early)
        $needResort = ($resortDaysLeft -gt 0) -and (
            ($consecutiveActive -ge 2) -or
            ($slotsRemaining -lt $resortDaysLeft)
        )

        if ($needResort) {
            $result += New-ResortDay $dayNum $hotelName
            $resortDaysLeft--
            $consecutiveActive  = 0
            $lastIntensity      = 'light'
            $dayNum++
            continue
        }

        # No more tour slots? fill with free days
        if ($tourSlotsLeft -le 0) {
            $result += New-FreeDayEntry $dayNum
            $dayNum++
            continue
        }

        # ── Pick best eligible tour ────────────────────────────────────────────
        # Pass 1: strict — different category AND no heavy-heavy
        $best = $null
        foreach ($t in $eligible) {
            $tid = [string]$t.id
            if ($scheduledIds -contains $tid) { continue }
            $ip        = Get-TourItineraryProfile $t
            $cat       = _SIP_GetStr $ip 'category' 'general'
            $intensity = _SIP_GetStr $ip 'intensity' 'moderate'
            if ($lastIntensity -eq 'heavy' -and $intensity -eq 'heavy') { continue }
            if ($usedCategories -contains $cat) { continue }
            $best = $t
            break
        }

        # Pass 2: relax category uniqueness (allow repeat category if needed)
        if ($null -eq $best) {
            foreach ($t in $eligible) {
                $tid = [string]$t.id
                if ($scheduledIds -contains $tid) { continue }
                $ip        = Get-TourItineraryProfile $t
                $intensity = _SIP_GetStr $ip 'intensity' 'moderate'
                if ($lastIntensity -eq 'heavy' -and $intensity -eq 'heavy') { continue }
                $best = $t
                break
            }
        }

        if ($null -ne $best) {
            $ip        = Get-TourItineraryProfile $best
            $cat       = _SIP_GetStr $ip 'category' 'general'
            $intensity = _SIP_GetStr $ip 'intensity' 'moderate'
            $desc      = _SIP_GetStr $best 'short_description' 'A curated private day experience in Guanacaste.'

            $entry = [PSCustomObject]@{
                day         = $dayNum
                title       = [string]$best.name
                description = $desc
                type        = $cat
                tour_id     = [string]$best.id
            }
            $result += $entry

            $scheduledIds    += [string]$best.id
            $usedCategories  += $cat
            $lastIntensity    = $intensity
            $consecutiveActive++
            $tourSlotsLeft--
        } else {
            # No eligible tours remain — fill with free day
            $result += New-FreeDayEntry $dayNum
            $consecutiveActive  = 0
            $lastIntensity      = 'light'
        }

        $dayNum++
    }

    # Last day: Departure (fixed)
    $result += New-DepartureDay $DurationDays $airportId

    return $result
}

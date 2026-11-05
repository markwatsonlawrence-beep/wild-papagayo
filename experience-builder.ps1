param(
    [Parameter(Mandatory)]
    [string]$HotelId
)

$ErrorActionPreference = 'Stop'
$root      = $PSScriptRoot
$filePath  = Join-Path $root "knowledge\master\hotels\$HotelId.json"

if (-not (Test-Path $filePath)) {
    Write-Host "Hotel not found: $filePath" -ForegroundColor Red
    exit 1
}

$Hotel = Get-Content $filePath -Raw -Encoding UTF8 | ConvertFrom-Json

$hotelName = if ($Hotel.identity.display_name)  { [string]$Hotel.identity.display_name }
             elseif ($Hotel.identity.official_name) { [string]$Hotel.identity.official_name }
             else { $HotelId }

$added = @()

# --- why_stay_here lives inside editorial (matches master JSON structure) ---
if ($Hotel.editorial -and -not $Hotel.editorial.why_stay_here) {
    $Hotel.editorial | Add-Member -NotePropertyName "why_stay_here" -NotePropertyValue ([PSCustomObject]@{
        title   = "Why Stay Here"
        summary = "$hotelName is one of the best places to stay if you want to combine comfort with unforgettable experiences around Guanacaste."
    })
    $added += "why_stay_here"
}

# --- Root-level content blocks ---
if (-not $Hotel.experience_highlights) {
    $Hotel | Add-Member -NotePropertyName "experience_highlights" -NotePropertyValue @(
        [PSCustomObject]@{ title = "Excellent Location";    description = "Easy access to Costa Rica's top attractions." },
        [PSCustomObject]@{ title = "Nature";                description = "Surrounded by tropical landscapes." },
        [PSCustomObject]@{ title = "Private Experiences";   description = "Ideal starting point for customized adventures." },
        [PSCustomObject]@{ title = "Relaxation";            description = "Perfect balance between exploration and rest." }
    )
    $added += "experience_highlights"
}

if (-not $Hotel.local_tips) {
    $Hotel | Add-Member -NotePropertyName "local_tips" -NotePropertyValue @(
        "Book tours early.",
        "Use sunscreen.",
        "Carry cash for small stops.",
        "Ask Wild Papagayo for local recommendations."
    )
    $added += "local_tips"
}

if (-not $Hotel.suggested_stay) {
    # Name the middle days after this hotel's actual featured tours (set by
    # hotel-autofill.ps1, which runs before this script) instead of generic
    # "Adventure" / "Beach" filler -- unique, real content reads better and
    # is worth more for SEO than templated placeholder text.
    $tourNames = @()
    foreach ($tourId in @($Hotel.recommendations.featured_tours)) {
        $tourPath = Join-Path $root "knowledge\tours\$tourId.json"
        if (Test-Path $tourPath) {
            $tour = Get-Content $tourPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($tour.name) { $tourNames += [string]$tour.name }
        }
    }

    $day2 = if ($tourNames.Count -ge 1) { [PSCustomObject]@{ day = 2; title = $tourNames[0]; description = "A recommended full-day experience with pickup from $hotelName." } }
            else { [PSCustomObject]@{ day = 2; title = "Adventure";  description = "Recommended full-day experience." } }
    $day3 = if ($tourNames.Count -ge 2) { [PSCustomObject]@{ day = 3; title = $tourNames[1]; description = "Another curated experience recommended for guests of $hotelName." } }
            else { [PSCustomObject]@{ day = 3; title = "Resort & Beach Day"; description = "Explore the resort, relax by the pool or on the beach, and recharge for the next adventure." } }

    $Hotel | Add-Member -NotePropertyName "suggested_stay" -NotePropertyValue @(
        [PSCustomObject]@{ day = 1; title = "Arrival";    description = "Transfer and relax." },
        $day2,
        $day3,
        [PSCustomObject]@{ day = 4; title = "Departure";  description = "Private airport transfer." }
    )
    $added += "suggested_stay"
}

if (-not $Hotel.planning) {
    $Hotel | Add-Member -NotePropertyName "planning" -NotePropertyValue ([PSCustomObject]@{
        ideal_stay      = "4-6 nights"
        transportation  = "Private Transfer"
        airport         = "LIR"
    })
    $added += "planning"
}

if (-not $Hotel.wild_recommendation) {
    $Hotel | Add-Member -NotePropertyName "wild_recommendation" -NotePropertyValue ([PSCustomObject]@{
        score   = 5
        summary = "Recommended by Wild Papagayo."
    })
    $added += "wild_recommendation"
}

# --- Ensure template field is set for generator routing ---
if (-not $Hotel.template) {
    $Hotel | Add-Member -NotePropertyName "template" -NotePropertyValue "experience"
    $added += "template"
}

$json = $Hotel | ConvertTo-Json -Depth 15
[System.IO.File]::WriteAllText($filePath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
if ($added.Count -eq 0) {
    Write-Host "Experience Guide is already complete -- no fields added." -ForegroundColor Cyan
} else {
    Write-Host "Experience Guide updated successfully." -ForegroundColor Green
    foreach ($field in $added) { Write-Host "  + $field" }
}
Write-Host ""
Write-Host $hotelName

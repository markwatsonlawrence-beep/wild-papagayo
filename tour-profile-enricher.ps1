# WEP 2.1 - Tour Profile Enricher
# Adds itinerary intelligence profiles to tour JSON files.
# Run once (or re-run to refresh). Idempotent - uses Add-Member -Force.
# PS5.1 compatible.

param(
    [string]$TourId = "",     # enrich a single tour (empty = all tours)
    [switch]$DryRun           # print changes without saving
)

$ErrorActionPreference = 'Stop'
$root     = $PSScriptRoot
$toursDir = Join-Path $root "knowledge\tours"

# ── Master profile table ──────────────────────────────────────────────────────
# pickup_zones: which hotel zones can pick up for this tour
#   "papagayo"     - Peninsula Papagayo area (Four Seasons, Andaz)
#   "playa-hermosa" - Playa Hermosa / Punta Cacique area (Waldorf)
#   "playa-coco"   - Playas del Coco area
#
# category:  itinerary category for scheduling rules (no repeat per stay)
# intensity: heavy | moderate | light  (no two heavy days in a row)
# priority:  0-100 base score (hotels add +20 for featured tours)
# min_stay / max_stay: eligible day range
# ideal_after / avoid_after: sequencing hints (soft guidance)

$Profiles = @{

    # ── Wildlife & Nature ────────────────────────────────────────────────────
    "hangingbridgessloths" = @{
        category    = "nature"
        intensity   = "moderate"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 95
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("arrival","resort")
        avoid_after = @("nature")
        tags        = @("wildlife","rainforest","sloths","suspension-bridges","waterfall")
    }
    "slothadventure" = @{
        category    = "wildlife"
        intensity   = "light"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 80
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("arrival","resort","adventure")
        avoid_after = @("wildlife")
        tags        = @("wildlife","sloths","rainforest","family")
    }
    "slothchocolatetour" = @{
        category    = "cultural"
        intensity   = "light"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 68
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("resort","adventure","nature")
        avoid_after = @("cultural")
        tags        = @("wildlife","sloths","chocolate","cultural","family")
    }
    "paloverderiverboattour" = @{
        category    = "wildlife"
        intensity   = "light"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 82
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("adventure","resort")
        avoid_after = @("wildlife")
        tags        = @("wildlife","birds","river","boat","crocodiles","mangrove")
    }
    "paloverdeculturalviejo" = @{
        category    = "cultural"
        intensity   = "light"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 65
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("resort","adventure","nature")
        avoid_after = @("cultural")
        tags        = @("wildlife","birds","river","cultural","rural")
    }
    "congotrail" = @{
        category    = "wildlife"
        intensity   = "moderate"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 72
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("resort","arrival")
        avoid_after = @("wildlife")
        tags        = @("wildlife","canopy","monkeys","zip-line","forest")
    }
    "floatingtenorio" = @{
        category    = "nature"
        intensity   = "light"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 68
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("resort","arrival")
        avoid_after = @("nature")
        tags        = @("river","floating","hot-springs","nature","relaxing")
    }

    # ── Waterfall & Hiking ────────────────────────────────────────────────────
    "celesteriver" = @{
        category    = "waterfall"
        intensity   = "moderate"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 88
        min_stay    = 4
        max_stay    = 14
        ideal_after = @("resort","wildlife")
        avoid_after = @("waterfall")
        tags        = @("waterfall","hiking","turquoise","celeste","nature","river")
    }
    "waterfalllovers" = @{
        category    = "waterfall"
        intensity   = "moderate"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 78
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("adventure","resort")
        avoid_after = @("waterfall")
        tags        = @("waterfall","hiking","nature","forest","swimming")
    }
    "waterfallpumas" = @{
        category    = "waterfall"
        intensity   = "moderate"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 75
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("resort","wildlife")
        avoid_after = @("waterfall")
        tags        = @("waterfall","hiking","nature","forest","river")
    }
    "tubingceleste" = @{
        category    = "adventure"
        intensity   = "moderate"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 74
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("resort","wildlife")
        avoid_after = @("adventure")
        tags        = @("tubing","river","adventure","celeste","water")
    }

    # ── Adventure ─────────────────────────────────────────────────────────────
    "buenavistamegacombo" = @{
        category    = "adventure"
        intensity   = "heavy"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 90
        min_stay    = 4
        max_stay    = 14
        ideal_after = @("resort","nature")
        avoid_after = @("adventure")
        tags        = @("combo","zip-line","hot-springs","horse","waterfall","volcano","cultural","full-day")
    }
    "haciendaguachipelin" = @{
        category    = "adventure"
        intensity   = "heavy"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 85
        min_stay    = 4
        max_stay    = 14
        ideal_after = @("nature","resort")
        avoid_after = @("adventure")
        tags        = @("zip-line","tubing","hot-springs","horse","combo","volcano","full-day")
    }
    "canyonadventurepark" = @{
        category    = "adventure"
        intensity   = "heavy"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 80
        min_stay    = 4
        max_stay    = 14
        ideal_after = @("nature","resort")
        avoid_after = @("adventure")
        tags        = @("zip-line","canopy","canyon","adventure","adrenaline")
    }
    "hikingrinconnationalpark" = @{
        category    = "adventure"
        intensity   = "heavy"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 82
        min_stay    = 4
        max_stay    = 14
        ideal_after = @("resort","wellness")
        avoid_after = @("adventure")
        tags        = @("volcano","hiking","national-park","rincon","crater","geothermal")
    }
    "congotrailcanopy" = @{
        category    = "adventure"
        intensity   = "moderate"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 75
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("resort","nature")
        avoid_after = @("adventure")
        tags        = @("canopy","zip-line","monkeys","forest","adrenaline")
    }
    "atvmountainride" = @{
        category    = "adventure"
        intensity   = "heavy"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 78
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("resort","wildlife")
        avoid_after = @("adventure")
        tags        = @("atv","mountain","off-road","adventure","views")
    }
    "canyoningtubing" = @{
        category    = "adventure"
        intensity   = "heavy"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 77
        min_stay    = 4
        max_stay    = 14
        ideal_after = @("resort","wildlife")
        avoid_after = @("adventure")
        tags        = @("canyoning","tubing","river","adventure","waterfall")
    }
    "coloradoriverrafting" = @{
        category    = "adventure"
        intensity   = "heavy"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 76
        min_stay    = 4
        max_stay    = 14
        ideal_after = @("resort","nature")
        avoid_after = @("adventure")
        tags        = @("rafting","river","rapids","adventure","water")
    }
    "tenoriorafting" = @{
        category    = "adventure"
        intensity   = "heavy"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 73
        min_stay    = 4
        max_stay    = 14
        ideal_after = @("resort","wildlife")
        avoid_after = @("adventure")
        tags        = @("rafting","tenorio","river","rapids","adventure")
    }
    # ── Rainforest & Arenal ───────────────────────────────────────────────────
    "arenalhangingbridges" = @{
        category    = "rainforest"
        intensity   = "moderate"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 86
        min_stay    = 5
        max_stay    = 14
        ideal_after = @("arrival","resort")
        avoid_after = @("rainforest")
        tags        = @("arenal","hanging-bridges","rainforest","volcano","wildlife","full-day")
    }
    "sensoriarainforest" = @{
        category    = "rainforest"
        intensity   = "light"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 65
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("resort","adventure")
        avoid_after = @("rainforest")
        tags        = @("rainforest","sensory","nature","walking","wellness","birdwatching")
    }
    "monteverdehangingbridgescoffee" = @{
        category    = "rainforest"
        intensity   = "moderate"
        pickup_zones = @("papagayo","playa-hermosa")
        priority    = 80
        min_stay    = 5
        max_stay    = 14
        ideal_after = @("arrival","resort")
        avoid_after = @("rainforest")
        tags        = @("monteverde","hanging-bridges","cloud-forest","coffee","full-day")
    }
    "monteverdtreetopwalk" = @{
        category    = "rainforest"
        intensity   = "moderate"
        pickup_zones = @("papagayo","playa-hermosa")
        priority    = 78
        min_stay    = 5
        max_stay    = 14
        ideal_after = @("resort","wellness")
        avoid_after = @("rainforest")
        tags        = @("monteverde","treetop","cloud-forest","canopy","wildlife")
    }

    # ── Wellness ──────────────────────────────────────────────────────────────
    "arenalhotsprings" = @{
        category    = "wellness"
        intensity   = "light"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 70
        min_stay    = 5
        max_stay    = 14
        ideal_after = @("adventure","nature")
        avoid_after = @("wellness")
        tags        = @("hot-springs","arenal","wellness","relaxation","volcano","spa")
    }
    "miravallesspa" = @{
        category    = "wellness"
        intensity   = "light"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 72
        min_stay    = 4
        max_stay    = 14
        ideal_after = @("adventure","nature")
        avoid_after = @("wellness")
        tags        = @("spa","wellness","hot-springs","miravalles","volcano","relaxation")
    }

    # ── Ocean & Catamaran ─────────────────────────────────────────────────────
    "laleona" = @{
        category    = "ocean"
        intensity   = "light"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 76
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("adventure","resort")
        avoid_after = @("ocean")
        tags        = @("catamaran","ocean","sunset","sailing","snorkeling","beach","pacific")
    }

    # ── Cultural & Experience ─────────────────────────────────────────────────
    "borinque4senses" = @{
        category    = "cultural"
        intensity   = "moderate"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 70
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("resort","nature")
        avoid_after = @("cultural")
        tags        = @("cultural","food","art","experience","local","community")
    }
    "haciendaaromal" = @{
        category    = "cultural"
        intensity   = "light"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 65
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("resort","adventure")
        avoid_after = @("cultural")
        tags        = @("hacienda","ranch","cultural","rural","cooking","horse")
    }
    "horsebackaromal" = @{
        category    = "cultural"
        intensity   = "light"
        pickup_zones = @("papagayo","playa-hermosa","playa-coco")
        priority    = 62
        min_stay    = 3
        max_stay    = 14
        ideal_after = @("resort","adventure")
        avoid_after = @("cultural")
        tags        = @("horseback","ranch","cultural","rural","hacienda")
    }
    "costaricahighlights" = @{
        category    = "cultural"
        intensity   = "moderate"
        pickup_zones = @("papagayo","playa-hermosa")
        priority    = 68
        min_stay    = 5
        max_stay    = 14
        ideal_after = @("resort","nature")
        avoid_after = @("cultural")
        tags        = @("highlights","signature","cultural","multi-destination","full-day")
    }
}

# ── Enrich tours ──────────────────────────────────────────────────────────────

$tourFiles = @(Get-ChildItem $toursDir -Filter "*.json")
if ($TourId -ne "") {
    $tourFiles = @($tourFiles | Where-Object { $_.BaseName -eq $TourId })
    if ($tourFiles.Count -eq 0) {
        Write-Host "No tour found with id: $TourId" -ForegroundColor Red
        exit 1
    }
}

$enriched  = 0
$skipped   = 0
$noProfile = 0

Write-Host ""
Write-Host "WEP 2.1 -- Tour Profile Enricher" -ForegroundColor Cyan
Write-Host ("Enriching {0} tours in: {1}" -f $tourFiles.Count, $toursDir)
Write-Host ""

foreach ($file in $tourFiles) {
    $id = $file.BaseName

    if (-not $Profiles.ContainsKey($id)) {
        Write-Host ("  [SKIP]   {0} -- no profile defined" -f $id) -ForegroundColor DarkGray
        $noProfile++
        continue
    }

    $raw  = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $tour = $raw | ConvertFrom-Json

    # Build itinerary PSObject from hashtable
    $profileHt  = $Profiles[$id]
    $profileObj = New-Object PSObject
    $profileObj | Add-Member -NotePropertyName 'category'     -NotePropertyValue $profileHt.category      -Force
    $profileObj | Add-Member -NotePropertyName 'intensity'    -NotePropertyValue $profileHt.intensity     -Force
    $profileObj | Add-Member -NotePropertyName 'pickup_zones' -NotePropertyValue $profileHt.pickup_zones  -Force
    $profileObj | Add-Member -NotePropertyName 'priority'     -NotePropertyValue $profileHt.priority      -Force
    $profileObj | Add-Member -NotePropertyName 'min_stay'     -NotePropertyValue $profileHt.min_stay      -Force
    $profileObj | Add-Member -NotePropertyName 'max_stay'     -NotePropertyValue $profileHt.max_stay      -Force
    $profileObj | Add-Member -NotePropertyName 'ideal_after'  -NotePropertyValue $profileHt.ideal_after   -Force
    $profileObj | Add-Member -NotePropertyName 'avoid_after'  -NotePropertyValue $profileHt.avoid_after   -Force
    $profileObj | Add-Member -NotePropertyName 'tags'         -NotePropertyValue $profileHt.tags          -Force

    # Check if already enriched with same data
    $existing = $tour.PSObject.Properties['itinerary']
    if ($null -ne $existing) {
        $existingCat = [string]$existing.Value.PSObject.Properties['category'].Value
        if ($existingCat -eq $profileHt.category) {
            Write-Host ("  [OK]     {0} -- already enriched" -f $id) -ForegroundColor DarkGray
            $skipped++
            continue
        }
    }

    if ($DryRun) {
        Write-Host ("  [DRY]    {0} -- would add: category={1} intensity={2} priority={3}" -f $id, $profileHt.category, $profileHt.intensity, $profileHt.priority) -ForegroundColor Yellow
        $enriched++
        continue
    }

    $tour | Add-Member -NotePropertyName 'itinerary' -NotePropertyValue $profileObj -Force

    $json = $tour | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($file.FullName, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("  [DONE]   {0} -- category={1} intensity={2} priority={3}" -f $id, $profileHt.category, $profileHt.intensity, $profileHt.priority) -ForegroundColor Green
    $enriched++
}

Write-Host ""
Write-Host ("Result: {0} enriched, {1} already up-to-date, {2} no profile defined" -f $enriched, $skipped, $noProfile) -ForegroundColor Cyan
if ($DryRun) { Write-Host "Dry run -- no files were modified." -ForegroundColor Yellow }
Write-Host ""
